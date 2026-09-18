# Plan-time guards. Resources that create nothing and exist only to carry preconditions — the
# checks a variable validation block cannot reach, because they need another entry in the map or a
# value that only a data source knows.

locals {
  # Two services in the same scope must not claim the same frontend IP configuration. Grouped by
  # "<scope>/<slot>" rather than compared pairwise via setproduct — Terraform's < operator only
  # accepts numbers, so the usual pair[0] < pair[1] trick for deduping cannot be used on map keys.
  slot_conflicts = {
    for slot, names in { for k, v in var.services : "${v.scope}/${v.frontend_ip_config}" => k... } :
    slot => names if length(names) > 1
  }

  # Claimed slot must be one the shared LB actually publishes for that scope.
  slot_unpublished = {
    for k, v in var.services : k => v.frontend_ip_config
    if !contains(keys(local.lb_frontend_ips[v.scope]), v.frontend_ip_config)
  }

  # A stopped server registered in a backend pool is a silent outage: the probe fails, the LB drops
  # it, and nothing in this repo's plan output says so. Windows makes this routine rather than
  # exotic — Update Manager reboots are exactly when someone applies unrelated Terraform and finds
  # a "healthy" plan against a pool with no live members. A service can opt out deliberately with
  # allow_stopped_vms.
  servers_not_running = {
    for k, v in local.server_addresses : k => v.power_state
    if lower(v.power_state) != "running" && !var.services[v.service].allow_stopped_vms
  }

  # A hostname outside the zone this repo can write produces a record that silently never resolves.
  hostnames_outside_zone = {
    for hostname, rec in local.dns_records : hostname => rec.service
    if !endswith(hostname, ".${local.dns_zone_name}")
  }

  # No resolvable private IP means the NIC has none, or the VM was found but is not networked the
  # way this repo assumes. Registering "" in a backend pool is accepted and then never works.
  servers_without_ip = {
    for k, v in local.server_addresses : k => v.vm_name
    if v.ip_address == null || v.ip_address == ""
  }
}

resource "terraform_data" "slot_guard" {
  lifecycle {
    precondition {
      condition     = length(local.slot_conflicts) == 0
      error_message = "Two services claim the same frontend IP configuration within a scope: ${jsonencode(local.slot_conflicts)}"
    }
    precondition {
      condition     = length(local.slot_unpublished) == 0
      error_message = "Service claims a frontend IP configuration the shared LB does not publish for its scope: ${jsonencode(local.slot_unpublished)}"
    }
  }
}

resource "terraform_data" "server_guard" {
  lifecycle {
    precondition {
      condition     = length(local.servers_not_running) == 0
      error_message = "Windows server is not running, so registering it in a backend pool would be a silent outage (set allow_stopped_vms on the service to accept this): ${jsonencode(local.servers_not_running)}"
    }
    precondition {
      condition     = length(local.servers_without_ip) == 0
      error_message = "Windows server has no resolvable private IP: ${jsonencode(local.servers_without_ip)}"
    }
  }
}

resource "terraform_data" "dns_guard" {
  lifecycle {
    precondition {
      condition     = length(local.hostnames_outside_zone) == 0
      error_message = "Hostname is outside the Private DNS zone this repo writes (${local.dns_zone_name}), so the record would never resolve: ${jsonencode(local.hostnames_outside_zone)}"
    }
  }
}

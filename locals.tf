locals {
  dns_zone_name           = nonsensitive(data.azurerm_app_configuration_key.dns_zone_name.value)
  dns_zone_resource_group = nonsensitive(data.azurerm_app_configuration_key.dns_zone_resource_group.value)
  vnet_id                 = nonsensitive(data.azurerm_app_configuration_key.vnet_id.value)

  # scope -> { frontend-config-name = "10.x.y.z" }
  lb_frontend_ips = {
    for scope, kv in data.azurerm_app_configuration_key.lb_frontend_ips :
    scope => jsondecode(nonsensitive(kv.value))
  }

  # Flattened "<service>/<vm>" index. Terraform's for_each needs a flat map, and flattening here
  # once keeps every downstream resource addressable by the same key — so a server added or removed
  # from a service moves exactly one address in state, not the whole service.
  server_index = merge([
    for svc_key, svc in var.services : {
      for vm in svc.vms : "${svc_key}/${vm.name}" => {
        service        = svc_key
        vm_name        = vm.name
        resource_group = coalesce(vm.resource_group, var.default_vm_resource_group)
      }
    }
  ]...)

  # Resolved backend addresses, keyed the same way.
  server_addresses = {
    for k, v in local.server_index : k => {
      service     = v.service
      vm_name     = v.vm_name
      ip_address  = data.azurerm_virtual_machine.server[k].private_ip_address
      power_state = data.azurerm_virtual_machine.server[k].power_state
    }
  }

  # Flattened DNS records: the canonical hostname plus any extras, all pointing at the frontend IP
  # the service claimed.
  dns_records = merge([
    for svc_key, svc in var.services : {
      for hostname in concat([svc.hostname], svc.extra_hostnames) : hostname => {
        service = svc_key
        # try(), not a direct index: an unpublished slot must reach the slot_unpublished
        # precondition in guards.tf, which names the service and the bad value. Indexing directly
        # here fails first with Terraform's "The given key does not identify an element in this
        # collection value", which says nothing about which service is wrong — the guard would be
        # unreachable in exactly the case it exists to explain.
        ip = try(local.lb_frontend_ips[svc.scope][svc.frontend_ip_config], "")
      }
    }
  ]...)
}

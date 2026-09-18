output "services" {
  description = "Per-service resolved facts, for cutover runbooks and for confirming what the LB actually points at."
  value = {
    for k, v in var.services : k => {
      hostname            = v.hostname
      frontend_ip         = try(local.lb_frontend_ips[v.scope][v.frontend_ip_config], "")
      frontend_ip_config  = v.frontend_ip_config
      scope               = v.scope
      load_balancer       = data.azurerm_lb.shared[v.scope].name
      backend_pool_id     = azurerm_lb_backend_address_pool.service[k].id
      session_persistence = v.session_persistence
      servers = [
        for sk, sv in local.server_addresses : {
          name        = sv.vm_name
          ip_address  = sv.ip_address
          power_state = sv.power_state
        } if sv.service == k
      ]
    }
  }
}

output "dns_records" {
  description = "Every name this repo writes, and the IP it resolves to."
  value       = { for hostname, rec in local.dns_records : hostname => rec.ip }
}

# The load balancer attachment. Three of the loadBalancers child types are independently
# deployable, which is the entire reason this repo can own a path onto a load balancer it does not
# own: azurerm_lb_backend_address_pool, _probe and _rule all take a loadbalancer_id.
#
# Worth knowing if anyone proposes porting this to Bicep: in ARM only backendAddressPools and
# inboundNatRules are deployable as children — probes, loadBalancingRules and
# frontendIPConfigurations all report `Permitted scopes for deployment: "none"` and must be declared
# inside the parent resource. Terraform manages them because the azurerm provider read-modify-writes
# the parent. This repo's shape is not expressible in Bicep.

resource "azurerm_lb_backend_address_pool" "service" {
  for_each = var.services
  provider = azurerm.lb

  name            = "bep-${each.key}"
  loadbalancer_id = data.azurerm_lb.shared[each.value.scope].id

  # IP-based pool: members are addresses, not NIC associations. This is what lets Terraform add a
  # server it does not own — a NIC-based pool would need azurerm to manage the network interface,
  # which belongs to whoever built the VM.
  virtual_network_id = local.vnet_id
}

resource "azurerm_lb_backend_address_pool_address" "server" {
  for_each = local.server_addresses
  provider = azurerm.lb

  name                    = each.value.vm_name
  backend_address_pool_id = azurerm_lb_backend_address_pool.service[each.value.service].id
  virtual_network_id      = local.vnet_id
  ip_address              = each.value.ip_address

  depends_on = [terraform_data.server_guard]
}

resource "azurerm_lb_probe" "service" {
  for_each = var.services
  provider = azurerm.lb

  name            = "probe-${each.key}"
  loadbalancer_id = data.azurerm_lb.shared[each.value.scope].id
  protocol        = each.value.health_protocol
  port            = each.value.target_port
  request_path    = each.value.health_protocol == "Tcp" ? null : each.value.health_path

  interval_in_seconds = 15
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "service" {
  for_each = var.services
  provider = azurerm.lb

  name            = "rule-${each.key}"
  loadbalancer_id = data.azurerm_lb.shared[each.value.scope].id

  protocol      = "Tcp"
  frontend_port = 443
  backend_port  = each.value.target_port

  frontend_ip_configuration_name = each.value.frontend_ip_config
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.service[each.key].id]
  probe_id                       = azurerm_lb_probe.service[each.key].id

  # Windows apps holding in-process session state need SourceIP; see the variable's comment.
  load_distribution = each.value.session_persistence

  idle_timeout_in_minutes = each.value.idle_timeout_minutes
  tcp_reset_enabled       = true
  disable_outbound_snat   = true

  depends_on = [terraform_data.slot_guard]
}

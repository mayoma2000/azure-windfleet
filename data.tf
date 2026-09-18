# The platform contract, read from App Configuration. Ownership-neutral keys under platform/*,
# labelled by environment. No cross-repo Terraform state access.

locals {
  scopes = distinct([for v in var.services : v.scope])
}

data "azurerm_app_configuration_key" "vnet_id" {
  configuration_store_id = var.app_config_id
  key                    = "platform/net/vnet-id"
  label                  = var.environment
}

data "azurerm_app_configuration_key" "lb_name" {
  for_each               = toset(local.scopes)
  configuration_store_id = var.app_config_id
  key                    = "platform/lb/${each.key}/name"
  label                  = var.environment
}

data "azurerm_app_configuration_key" "lb_resource_group" {
  for_each               = toset(local.scopes)
  configuration_store_id = var.app_config_id
  key                    = "platform/lb/${each.key}/resource-group"
  label                  = var.environment
}

# name -> private IP of every frontend IP configuration the shared LB pre-provisions. A service
# claims one by name; the DNS record points at its IP. This is the published-range counterpart of
# the AWS repo's /platform/lb/<scope>/priority-range.
data "azurerm_app_configuration_key" "lb_frontend_ips" {
  for_each               = toset(local.scopes)
  configuration_store_id = var.app_config_id
  key                    = "platform/lb/${each.key}/frontend-ips"
  label                  = var.environment
}

data "azurerm_app_configuration_key" "dns_zone_name" {
  configuration_store_id = var.app_config_id
  key                    = "platform/dns/${var.environment}/private-zone-name"
  label                  = var.environment
}

data "azurerm_app_configuration_key" "dns_zone_resource_group" {
  configuration_store_id = var.app_config_id
  key                    = "platform/dns/${var.environment}/private-zone-resource-group"
  label                  = var.environment
}

# The shared load balancers, looked up rather than created.
data "azurerm_lb" "shared" {
  for_each = toset(local.scopes)
  provider = azurerm.lb

  name                = nonsensitive(data.azurerm_app_configuration_key.lb_name[each.key].value)
  resource_group_name = nonsensitive(data.azurerm_app_configuration_key.lb_resource_group[each.key].value)
}

# The Windows servers. Resolving them here is the point of the whole design: a name that does not
# exist fails at PLAN time rather than producing a backend pool that silently points nowhere, and
# power_state feeds the running-state guard. Mirrors the AWS repo's data "aws_instance" validation
# on manual_targets.
data "azurerm_virtual_machine" "server" {
  for_each = local.server_index

  name                = each.value.vm_name
  resource_group_name = each.value.resource_group
}

# azurerm 5.x addresses a private DNS record by zone ID, not zone_name + resource_group_name. The
# zone NAME is still needed to trim the suffix off a service's FQDN and to validate it, so the
# contract keeps publishing both and the ID is resolved here.
data "azurerm_private_dns_zone" "private" {
  provider = azurerm.dns

  name                = local.dns_zone_name
  resource_group_name = local.dns_zone_resource_group
}

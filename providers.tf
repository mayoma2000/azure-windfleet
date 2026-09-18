provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# The shared load balancer lives in the platform subscription, the Private DNS zones in the hub.
# Both are owned by other repos; this one only attaches to them.
provider "azurerm" {
  alias = "lb"
  features {}
  subscription_id = var.lb_subscription_id
}

provider "azurerm" {
  alias = "dns"
  features {}
  subscription_id = var.dns_subscription_id
}

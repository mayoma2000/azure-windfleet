# Environment: nonprod.
environment = "nonprod"

subscription_id     = "00000000-0000-0000-0000-000000000000" # REPLACE
lb_subscription_id  = "00000000-0000-0000-0000-000000000000" # REPLACE
dns_subscription_id = "00000000-0000-0000-0000-000000000000" # REPLACE

app_config_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-uvi-platform/providers/Microsoft.AppConfiguration/configurationStores/uvi-platform-config"

default_vm_resource_group = "rg-uvi-windows-nonprod"

tags = {
  environment = "nonprod"
  managedBy   = "azure-windfleet"
  lifecycle   = "migration-bridge"
}

# One service with one server is enough to prove the chain: VM lookup -> backend pool -> probe ->
# rule -> frontend IP -> Private DNS. Add a second VM to also prove HA.
services = {}

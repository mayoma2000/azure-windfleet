# Environment: prod. Non-secret values only (this file is committed).
environment = "prod"

subscription_id     = "00000000-0000-0000-0000-000000000000" # REPLACE: Windows workload subscription
lb_subscription_id  = "00000000-0000-0000-0000-000000000000" # REPLACE: platform subscription
dns_subscription_id = "00000000-0000-0000-0000-000000000000" # REPLACE: hub subscription

app_config_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-uvi-platform/providers/Microsoft.AppConfiguration/configurationStores/uvi-platform-config"

default_vm_resource_group = "rg-uvi-windows-prod"

tags = {
  environment = "prod"
  managedBy   = "azure-windfleet"
  lifecycle   = "migration-bridge"
}

services = {
  # Template. Copy, fill in, and onboard ONE service at a time — plan, apply, verify the probe goes
  # healthy, then move on. The servers must already exist and be running.
  #
  # winapp = {
  #   hostname           = "winapp.svc.prod.aws.sandals.net"
  #   scope              = "internal"
  #   frontend_ip_config = "fe-2001"   # unique in this scope, published by the shared LB
  #   target_port        = 443
  #   health_protocol    = "Https"
  #   health_path        = "/health"
  #
  #   # Built and maintained by sysadmins; this repo only points the LB at them.
  #   vms = [
  #     { name = "awspwinapp1" },
  #     { name = "awspwinapp2" },
  #   ]
  #
  #   # REQUIRED for classic ASP.NET/IIS InProc sessions — node-local state means a round-robin
  #   # rule logs users out at random. Leave "Default" only if the app is genuinely stateless.
  #   session_persistence = "SourceIP"
  # }
}

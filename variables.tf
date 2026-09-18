variable "subscription_id" {
  description = "Subscription holding the Windows servers this repo attaches to the shared LB."
  type        = string
}

variable "lb_subscription_id" {
  description = "Subscription holding the shared load balancer (owned by the shared-lb repo)."
  type        = string
}

variable "dns_subscription_id" {
  description = "Subscription holding the Private DNS zones (owned by the dns repo)."
  type        = string
}

variable "environment" {
  description = "Selects the contract label and the state key."
  type        = string

  validation {
    condition     = contains(["nonprod", "prod"], var.environment)
    error_message = "environment must be nonprod or prod (PCI gets its own repo)."
  }
}

variable "app_config_id" {
  description = "Resource ID of the App Configuration store holding the platform/* contract."
  type        = string
}

variable "default_vm_resource_group" {
  description = "Resource group the Windows servers live in, when a service does not override it."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource this repo owns."
  type        = map(string)
  default     = {}
}

variable "services" {
  description = <<-EOT
    One entry per Windows application to put behind the shared load balancer.

    This repo does NOT create the virtual machines. Each entry names servers that already exist —
    built and maintained by sysadmins over RDP/WinRM, domain-joined, patched by Update Manager —
    and Terraform owns only the path to them: backend pool membership, health probe, load-balancing
    rule and the DNS record. See README for why the guest is deliberately out of scope.

    Naming servers rather than IPs is what makes a typo a plan-time error: the VM is resolved
    through a data source, so a name that does not exist fails before anything is created, and the
    address in the backend pool can never drift from the machine it is supposed to point at.
  EOT

  type = map(object({
    hostname = string # canonical FQDN; gets the Private DNS A record

    scope = string # internal | external — which shared LB to attach to

    # The pre-provisioned frontend IP configuration this service claims on the shared LB. Unique
    # within its scope, and a member of the range that scope publishes.
    frontend_ip_config = string

    # The Windows servers. >= 2 for HA; they must already exist and be running.
    vms = list(object({
      name           = string
      resource_group = optional(string) # null = var.default_vm_resource_group
    }))

    target_port     = optional(number, 443)
    health_protocol = optional(string, "Https")
    health_path     = optional(string, "/")

    # Session persistence. "SourceIP" is REQUIRED, not optional, for any Windows app holding
    # in-process session state — classic ASP.NET/IIS InProc sessions are node-local, so a
    # round-robin rule logs users out at random. Default matches the LB default (5-tuple).
    session_persistence = optional(string, "Default")

    idle_timeout_minutes = optional(number, 30)

    # Extra Private DNS A records pointing at the same frontend IP.
    extra_hostnames = optional(list(string), [])

    # A service whose servers are deliberately stopped (seasonal, DR standby) opts out of the
    # running-state guard. Set consciously — see guards.tf.
    allow_stopped_vms = optional(bool, false)
  }))

  default = {}

  validation {
    condition     = alltrue([for k, v in var.services : contains(["internal", "external"], v.scope)])
    error_message = "Each service's scope must be internal or external."
  }

  validation {
    condition     = alltrue([for k, v in var.services : length(v.vms) >= 1])
    error_message = "Each service must name at least one VM (use >= 2 for HA)."
  }

  validation {
    condition     = alltrue([for k, v in var.services : contains(["Http", "Https", "Tcp"], v.health_protocol)])
    error_message = "health_protocol must be Http, Https or Tcp."
  }

  validation {
    condition = alltrue([
      for k, v in var.services : contains(["Default", "SourceIP", "SourceIPProtocol"], v.session_persistence)
    ])
    error_message = "session_persistence must be Default, SourceIP or SourceIPProtocol."
  }

  validation {
    condition     = alltrue([for k, v in var.services : can(regex("^[a-z0-9-]{1,40}$", k))])
    error_message = "Service keys are used in resource names: lowercase letters, digits and hyphens only."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.services : [for vm in v.vms : length(vm.name) > 0]
    ]))
    error_message = "Every VM entry needs a non-empty name."
  }
}

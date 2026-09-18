# azure-windfleet

Terraform that puts **existing Windows servers** behind the shared internal load balancer in Azure, and gives them a name.

One entry per application. From that entry this repo produces a backend address pool, a health probe, a load-balancing rule on the shared LB, and a Private DNS A record.

**Lifecycle:** TEMPORARY bridge — retired as applications move to containers on AKS. Build everything to delete as cleanly as it was created.

```bash
terraform init -backend-config="key=platform/azure-windfleet/prod/terraform.tfstate"
terraform plan -var-file=envs/prod.tfvars
```

## The scope decision — read this first

**This repo does not create virtual machines, and that is deliberate.**

The Windows servers are built and maintained by sysadmins over RDP/WinRM: domain-joined, GPO-managed, patched by Update Manager. Terraform owns only the *path* to them.

That is the shape the AWS estate actually converged on. In `terraform-shared-lb`, nine of the ten original `terraform-ec2-fleets` entries now also exist as `manual_targets`, and the comment on the first one to cut over says it plainly:

> *"Moved off the ec2-fleets instance onto the sysadmin-built pair awspachwb1/wb2 […] the VMs are maintained over SSH and only the load balancer is terraform."*

Windows makes the case stronger, not weaker. A domain-joined server's lifecycle is owned by AD, GPO and Update Manager — three systems Terraform cannot see. A repo that also declared the VM would fight all three, and would show drift every patch Tuesday.

**In scope:** backend pool membership, probes, load-balancing rules, Private DNS records, the cross-entry guards.

**Out of scope:** VMs, NICs, disks, domain join, the guest OS. Also NSGs — an NSG attaches to a NIC or a subnet, and this repo owns neither; subnet NSGs belong to the network repo.

If you later need Terraform to build the VMs too, the seam is `var.services[*].vms`: replace the data-source lookup in `data.tf` with a VM resource and feed the same IPs into `azurerm_lb_backend_address_pool_address`. Nothing else changes.

## Layout

| File | What |
|---|---|
| `variables.tf` | The `services` schema and its validations |
| `data.tf` | The `platform/*` contract, the shared LBs, and the Windows VMs |
| `locals.tf` | Flattening and resolved addresses |
| `guards.tf` | Cross-entry and live-state preconditions |
| `main.tf` | Backend pool, pool addresses, probe, rule |
| `dns.tf` | Private DNS A records |
| `envs/*.tfvars` | Per-environment service declarations |

## The service declaration

```hcl
services = {
  winapp = {
    hostname           = "winapp.svc.prod.aws.sandals.net"
    scope              = "internal"
    frontend_ip_config = "fe-2001"
    target_port        = 443
    health_protocol    = "Https"
    health_path        = "/health"

    vms = [
      { name = "awspwinapp1" },
      { name = "awspwinapp2" },
    ]

    session_persistence = "SourceIP"
  }
}
```

### Servers are named, not addressed

`vms` takes machine **names**, and the IP is resolved through `data "azurerm_virtual_machine"`. This is the single most useful property of the design:

- A typo or a decommissioned server fails at **plan time**, not as a backend pool quietly pointing nowhere
- The registered address can never drift from the machine it is meant to point at
- `power_state` comes back with it, which feeds the running-state guard below

It mirrors the `data "aws_instance"` validation on the AWS repo's `manual_targets`, and for the same reason: *"fails early on typos or resources that don't exist yet, rather than surfacing errors only at apply."*

### `session_persistence` is not a nicety

`"SourceIP"` is **required** for any Windows app holding in-process session state. Classic ASP.NET/IIS `InProc` sessions are node-local, so a round-robin rule logs users out at random once you have two servers. The AWS repo learned this the same way — its note on the first two-node manual target says stickiness there is *"REQUIRED here, not optional."*

Leave `"Default"` only if the app is genuinely stateless or keeps session in SQL/Redis.

## Cross-repo contract

Consumes from App Configuration under `platform/*`, publishes nothing:

- `platform/lb/<scope>/name`, `/resource-group`, `/frontend-ips`
- `platform/dns/<env>/private-zone-name`, `/private-zone-resource-group`
- `platform/net/vnet-id`

`frontend-ips` is a JSON map of frontend-config name → private IP. A service claims one by name; the DNS record points at that IP, so replacing a Windows server never touches DNS.

## Guards

All five were exercised against deliberately broken input, not just written:

| Guard | Fires when | Why it matters |
|---|---|---|
| `slot_conflicts` | Two services claim one frontend IP config in a scope | Second apply silently steals the first service's traffic |
| `slot_unpublished` | Claimed slot is not in the published set | Rule would reference a frontend that does not exist |
| `servers_not_running` | A named VM is not `running` | **A stopped server in a backend pool is a silent outage** — the probe fails, the LB drops it, and the plan says nothing. Windows makes this routine: Update Manager reboots are exactly when someone applies unrelated Terraform. Opt out per service with `allow_stopped_vms` |
| `servers_without_ip` | A VM resolves with no private IP | `""` is accepted into a pool and then never works |
| `hostnames_outside_zone` | An FQDN is outside the writable zone | Record silently never resolves |

One implementation note worth keeping: `locals.tf` resolves the frontend IP with `try()`, not a direct index. Indexing directly meant an unpublished slot blew up in `locals.tf` with Terraform's generic *"The given key does not identify an element in this collection value"* — which names no service — **before** `slot_unpublished` could produce its useful message. The guard was unreachable in exactly the case it exists to explain. Do not "simplify" that `try()` away.

## Why Terraform and not Bicep

Three of the `loadBalancers` child types are independently deployable in Terraform because the `azurerm` provider read-modify-writes the parent, which is what lets this repo own a path onto a load balancer it does not own.

ARM cannot do it. Only `backendAddressPools` and `inboundNatRules` are deployable as ARM children; `probes`, `loadBalancingRules` and `frontendIPConfigurations` all report `Permitted scopes for deployment: "none"` and must be declared inside the parent resource. **This repo's shape is not expressible in Bicep** — a Bicep version would have to move every service's probe and rule into whichever template owns the LB.

Terraform is also the only side with Site Recovery resources (16 in `azurerm` 5.6.0, zero for `Microsoft.OffAzure`), so if replication plumbing ever lands in IaC it can live alongside this.

## Onboarding a service

One at a time. Plan, apply, confirm the probe goes healthy, then move on.

1. Confirm the servers exist, are running, and answer on `target_port` from another machine in the VNet
2. Claim a free `frontend_ip_config` from the scope's published set
3. Decide `session_persistence` **with the application owner**, not by default
4. Add the entry to `envs/<env>.tfvars`, `terraform plan`, review, apply
5. Verify the probe is healthy and the DNS name resolves to the frontend IP
6. Only then point real traffic at the name

For the migration itself — replication, test failover, cutover, and the Windows gotchas — see the pilot runbook; none of that is Terraform's job.

## Verified

`terraform fmt -check -recursive` clean and `terraform validate` passing against `azurerm` 5.6.0, with all five guards exercised against broken input (duplicate slot, unpublished slot, deallocated VM, VM with no IP, hostname outside the zone) and the `allow_stopped_vms` opt-out confirmed to suppress only its own service.

Nothing has been applied. A real `plan` needs the `platform/*` App Configuration keys to exist first.

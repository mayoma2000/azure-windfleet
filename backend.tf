# Azure Blob leases the state file natively, so there is no DynamoDB/use_lockfile analog to
# configure — the lock is a property of the blob.
#
#   terraform init -backend-config="key=platform/azure-windfleet/prod/terraform.tfstate"
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-uvi-terraform-state"
    storage_account_name = "uviterraformstatecac"
    container_name       = "tfstate"
    use_azuread_auth     = true
  }
}

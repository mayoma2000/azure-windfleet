# Private DNS A records, written in the hub subscription through the aliased provider. Each record
# points at the private IP of the frontend configuration its service claimed — not at a server, so
# adding or replacing a Windows box never touches DNS.

resource "azurerm_private_dns_a_record" "service" {
  for_each = local.dns_records
  provider = azurerm.dns

  name                = trimsuffix(trimsuffix(each.key, local.dns_zone_name), ".")
  private_dns_zone_id = data.azurerm_private_dns_zone.private.id
  ttl                 = 60
  records             = [each.value.ip]
  tags                = var.tags

  depends_on = [terraform_data.dns_guard]
}

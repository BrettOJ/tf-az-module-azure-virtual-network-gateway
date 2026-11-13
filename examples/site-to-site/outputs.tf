output "gateway_resource_id" {
  value       = module.gateway.resource_id
  description = "Gateway ID for connection resources."
}
output "public_ip_addresses" {
  value       = { for key, pip in azurerm_public_ip.gateway : key => pip.ip_address }
  description = "Public IPs for configuring remote VPN devices."
}
output "bgp_settings" {
  value       = module.gateway.bgp_settings
  description = "BGP addresses assigned by Azure."
}

output "local_network_gateway_resource_ids" {
  value       = module.gateway.local_network_gateway_resource_ids
  description = "Remote-site representation resource IDs."
}
output "site_to_site_connection_resource_ids" {
  value       = module.gateway.site_to_site_connection_resource_ids
  description = "IPsec connection resource IDs."
}

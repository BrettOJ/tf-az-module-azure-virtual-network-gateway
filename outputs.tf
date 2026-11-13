output "resource_id" {
  value       = azurerm_virtual_network_gateway.this.id
  description = "Gateway resource ID for connections and downstream modules."
}
output "name" {
  value       = azurerm_virtual_network_gateway.this.name
  description = "Gateway name."
}
output "bgp_settings" {
  value       = azurerm_virtual_network_gateway.this.bgp_settings
  description = "Computed BGP settings including peering and tunnel IP addresses."
}
output "ip_configuration" {
  value       = azurerm_virtual_network_gateway.this.ip_configuration
  description = "Gateway IP configuration details."
}

output "local_network_gateway_resource_ids" {
  value       = { for key, gateway in azurerm_local_network_gateway.this : key => gateway.id }
  description = "Created local network gateway IDs keyed by local_network_gateways map keys."
}
output "site_to_site_connection_resource_ids" {
  value       = { for key, connection in azurerm_virtual_network_gateway_connection.this : key => connection.id }
  description = "S2S connection IDs keyed by site_to_site_connections map keys. No shared secrets are exported."
}

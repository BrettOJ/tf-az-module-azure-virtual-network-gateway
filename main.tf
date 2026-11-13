resource "azurerm_virtual_network_gateway" "this" {
  name                             = var.name
  location                         = var.location
  resource_group_name              = var.resource_group_name
  type                             = var.type
  sku                              = var.sku
  vpn_type                         = var.vpn_type
  generation                       = var.generation
  active_active                    = var.active_active
  bgp_enabled                      = var.bgp_enabled
  default_local_network_gateway_id = var.default_local_network_gateway_id
  private_ip_address_enabled       = var.private_ip_address_enabled
  tags                             = var.tags

  dynamic "ip_configuration" {
    for_each = var.ip_configurations
    content {
      name                          = ip_configuration.value.name
      subnet_id                     = ip_configuration.value.subnet_id
      public_ip_address_id          = ip_configuration.value.public_ip_address_id
      private_ip_address_allocation = "Dynamic"
    }
  }
  dynamic "bgp_settings" {
    for_each = var.bgp_settings == null ? [] : [var.bgp_settings]
    content {
      asn         = bgp_settings.value.asn
      peer_weight = bgp_settings.value.peer_weight
      dynamic "peering_addresses" {
        for_each = bgp_settings.value.peering_addresses
        content {
          ip_configuration_name = peering_addresses.value.ip_configuration_name
          apipa_addresses       = peering_addresses.value.apipa_addresses
        }
      }
    }
  }
  dynamic "custom_route" {
    for_each = length(var.custom_route_address_prefixes) == 0 ? [] : [var.custom_route_address_prefixes]
    content { address_prefixes = custom_route.value }
  }
  dynamic "vpn_client_configuration" {
    for_each = var.vpn_client_configuration == null ? [] : [var.vpn_client_configuration]
    content {
      address_space        = vpn_client_configuration.value.address_space
      vpn_client_protocols = vpn_client_configuration.value.vpn_client_protocols
      vpn_auth_types       = vpn_client_configuration.value.vpn_auth_types
      aad_tenant           = vpn_client_configuration.value.aad_tenant
      aad_audience         = vpn_client_configuration.value.aad_audience
      aad_issuer           = vpn_client_configuration.value.aad_issuer
      dynamic "root_certificate" {
        for_each = vpn_client_configuration.value.root_certificates
        content {
          name             = root_certificate.key
          public_cert_data = root_certificate.value.public_cert_data
        }
      }
      dynamic "revoked_certificate" {
        for_each = vpn_client_configuration.value.revoked_certificates
        content {
          name       = revoked_certificate.key
          thumbprint = revoked_certificate.value.thumbprint
        }
      }
    }
  }
  timeouts {
    create = var.timeouts.create
    read   = var.timeouts.read
    update = var.timeouts.update
    delete = var.timeouts.delete
  }
  lifecycle {
    precondition {
      condition     = length(var.ip_configurations) == (var.active_active ? (var.vpn_client_configuration != null && endswith(var.sku, "AZ") ? 3 : 2) : 1)
      error_message = "Expected one IP configuration for standby, two for active-active, or three for active-active AZ P2S."
    }
    precondition {
      condition     = var.type == "Vpn" ? alltrue([for v in var.ip_configurations : v.public_ip_address_id != null]) : alltrue([for v in var.ip_configurations : v.public_ip_address_id == null])
      error_message = "VPN requires public IP IDs; ExpressRoute must omit them in AzureRM 5.13."
    }
    precondition {
      condition     = var.type == "Vpn" || (!var.active_active && var.vpn_client_configuration == null)
      error_message = "active_active and P2S configuration are VPN-only options."
    }
    precondition {
      condition     = var.vpn_type != "PolicyBased" || (var.sku == "Basic" && !var.active_active && !var.bgp_enabled)
      error_message = "PolicyBased requires Basic with active-active and BGP disabled."
    }
    precondition {
      condition     = var.bgp_settings == null || var.bgp_enabled
      error_message = "Enable BGP when supplying bgp_settings."
    }
  }
}

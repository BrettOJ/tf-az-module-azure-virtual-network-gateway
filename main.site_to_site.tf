resource "azurerm_local_network_gateway" "this" {
  for_each            = var.local_network_gateways
  name                = each.value.name
  location            = var.location
  resource_group_name = var.resource_group_name
  gateway_address     = each.value.gateway_address
  gateway_fqdn        = each.value.gateway_fqdn
  address_space       = each.value.address_space
  tags                = merge(var.tags, each.value.tags)
  dynamic "bgp_settings" {
    for_each = each.value.bgp_settings == null ? [] : [each.value.bgp_settings]
    content {
      asn                 = bgp_settings.value.asn
      bgp_peering_address = bgp_settings.value.bgp_peering_address
      peer_weight         = bgp_settings.value.peer_weight
    }
  }
}

resource "azurerm_virtual_network_gateway_connection" "this" {
  for_each                           = var.site_to_site_connections
  name                               = each.value.name
  location                           = var.location
  resource_group_name                = var.resource_group_name
  type                               = "IPsec"
  virtual_network_gateway_id         = azurerm_virtual_network_gateway.this.id
  local_network_gateway_id           = each.value.local_network_gateway_id != null ? each.value.local_network_gateway_id : try(azurerm_local_network_gateway.this[each.value.local_network_gateway_key].id, null)
  shared_key                         = lookup(var.site_to_site_shared_keys, each.key, null)
  connection_protocol                = each.value.connection_protocol
  connection_mode                    = each.value.connection_mode
  bgp_enabled                        = each.value.bgp_enabled
  routing_weight                     = each.value.routing_weight
  dpd_timeout_seconds                = each.value.dpd_timeout_seconds
  local_azure_ip_address_enabled     = each.value.local_azure_ip_address_enabled
  use_policy_based_traffic_selectors = each.value.use_policy_based_traffic_selectors
  tags                               = merge(var.tags, each.value.tags)

  dynamic "ipsec_policy" {
    for_each = each.value.ipsec_policy == null ? [] : [each.value.ipsec_policy]
    content {
      dh_group         = ipsec_policy.value.dh_group
      ike_encryption   = ipsec_policy.value.ike_encryption
      ike_integrity    = ipsec_policy.value.ike_integrity
      ipsec_encryption = ipsec_policy.value.ipsec_encryption
      ipsec_integrity  = ipsec_policy.value.ipsec_integrity
      pfs_group        = ipsec_policy.value.pfs_group
      sa_datasize      = ipsec_policy.value.sa_datasize
      sa_lifetime      = ipsec_policy.value.sa_lifetime
    }
  }
  dynamic "traffic_selector_policy" {
    for_each = each.value.traffic_selector_policies
    content {
      local_address_cidrs  = traffic_selector_policy.value.local_address_cidrs
      remote_address_cidrs = traffic_selector_policy.value.remote_address_cidrs
    }
  }
  dynamic "custom_bgp_addresses" {
    for_each = each.value.custom_bgp_addresses == null ? [] : [each.value.custom_bgp_addresses]
    content {
      primary   = custom_bgp_addresses.value.primary
      secondary = custom_bgp_addresses.value.secondary
    }
  }
  lifecycle {
    precondition {
      condition     = var.type == "Vpn"
      error_message = "Site-to-site IPsec connections require type = Vpn."
    }
    precondition {
      condition     = try(length(trimspace(var.site_to_site_shared_keys[each.key])) > 0, false)
      error_message = "Provide a non-empty site_to_site_shared_keys entry for every connection key."
    }
    precondition {
      condition     = !each.value.bgp_enabled || var.bgp_enabled
      error_message = "Enable BGP on the virtual network gateway before enabling connection BGP."
    }
    precondition {
      condition     = each.value.local_network_gateway_key == null ? true : (!each.value.bgp_enabled || try(var.local_network_gateways[each.value.local_network_gateway_key].bgp_settings != null, false))
      error_message = "A module-created local network gateway needs bgp_settings when connection BGP is enabled."
    }
    precondition {
      condition     = each.value.local_network_gateway_key == null ? true : (each.value.bgp_enabled || try(length(var.local_network_gateways[each.value.local_network_gateway_key].address_space) > 0, false))
      error_message = "Static-routing connections require remote address_space on the module-created local network gateway."
    }
    precondition {
      condition     = !each.value.local_azure_ip_address_enabled || var.private_ip_address_enabled
      error_message = "Enable private_ip_address_enabled on the gateway to use its private IP for this connection."
    }
    precondition {
      condition     = each.value.custom_bgp_addresses == null || (var.active_active && each.value.bgp_enabled)
      error_message = "custom_bgp_addresses requires active-active mode and connection BGP."
    }
  }
}

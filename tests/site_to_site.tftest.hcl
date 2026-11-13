mock_provider "azurerm" {}
variables {
  name                = "vgw-test"
  location            = "southeastasia"
  resource_group_name = "rg-test"
  ip_configurations = {
    primary = {
      name                 = "primary"
      subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/GatewaySubnet"
      public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/publicIPAddresses/pip-test"
    }
  }
}
run "gateway_only_remains_default" {
  command = plan
  assert {
    condition     = length(azurerm_local_network_gateway.this) == 0 && length(azurerm_virtual_network_gateway_connection.this) == 0
    error_message = "New S2S resources must remain optional."
  }
}
run "managed_site_with_custom_policy" {
  command = plan
  variables {
    local_network_gateways = {
      branch = { name = "lng-branch", gateway_address = "203.0.113.10", address_space = ["192.168.10.0/24"] }
    }
    site_to_site_connections = {
      branch = {
        name                               = "conn-branch"
        local_network_gateway_key          = "branch"
        use_policy_based_traffic_selectors = true
        ipsec_policy = {
          dh_group         = "DHGroup14"
          ike_encryption   = "AES256"
          ike_integrity    = "SHA256"
          ipsec_encryption = "AES256"
          ipsec_integrity  = "SHA256"
          pfs_group        = "PFS14"
        }
        traffic_selector_policies = [{ local_address_cidrs = ["10.80.0.0/16"], remote_address_cidrs = ["192.168.10.0/24"] }]
      }
    }
    site_to_site_shared_keys = { branch = "DummyTestKeyOnly123456789" }
  }
  assert {
    condition     = azurerm_virtual_network_gateway_connection.this["branch"].type == "IPsec" && azurerm_virtual_network_gateway_connection.this["branch"].connection_protocol == "IKEv2"
    error_message = "Expected an IKEv2 IPsec connection."
  }
  assert {
    condition     = length(azurerm_local_network_gateway.this) == 1 && length(azurerm_virtual_network_gateway_connection.this["branch"].ipsec_policy) == 1 && length(azurerm_virtual_network_gateway_connection.this["branch"].traffic_selector_policy) == 1
    error_message = "Expected one managed site, custom policy and traffic selectors."
  }
}
run "existing_site" {
  command = plan
  variables {
    site_to_site_connections = {
      existing = {
        name                     = "conn-existing"
        local_network_gateway_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/localNetworkGateways/lng-existing"
      }
    }
    site_to_site_shared_keys = { existing = "DummyTestKeyOnly123456789" }
  }
  assert {
    condition     = length(azurerm_local_network_gateway.this) == 0 && endswith(azurerm_virtual_network_gateway_connection.this["existing"].local_network_gateway_id, "/lng-existing")
    error_message = "Existing local network gateway must be reused."
  }
}
run "bgp_site_with_fqdn" {
  command = plan
  variables {
    bgp_enabled  = true
    bgp_settings = { asn = 65515 }
    local_network_gateways = {
      branch = {
        name         = "lng-branch"
        gateway_fqdn = "vpn.example.com"
        bgp_settings = { asn = 65010, bgp_peering_address = "192.168.10.254" }
      }
    }
    site_to_site_connections = { branch = { name = "conn-branch", local_network_gateway_key = "branch", bgp_enabled = true } }
    site_to_site_shared_keys = { branch = "DummyTestKeyOnly123456789" }
  }
  assert {
    condition     = azurerm_virtual_network_gateway_connection.this["branch"].bgp_enabled && azurerm_local_network_gateway.this["branch"].gateway_fqdn == "vpn.example.com"
    error_message = "Expected BGP connection using the remote FQDN."
  }
}
run "missing_shared_key_is_rejected" {
  command = plan
  variables {
    site_to_site_connections = {
      existing = {
        name                     = "conn-existing"
        local_network_gateway_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/localNetworkGateways/lng-existing"
      }
    }
  }
  expect_failures = [azurerm_virtual_network_gateway_connection.this["existing"]]
}
run "both_site_references_are_rejected" {
  command = plan
  variables {
    local_network_gateways = { branch = { name = "lng-branch", gateway_address = "203.0.113.10", address_space = ["192.168.10.0/24"] } }
    site_to_site_connections = {
      branch = {
        name                      = "conn-branch"
        local_network_gateway_key = "branch"
        local_network_gateway_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/localNetworkGateways/lng-existing"
      }
    }
    site_to_site_shared_keys = { branch = "DummyTestKeyOnly123456789" }
  }
  expect_failures = [var.site_to_site_connections]
}

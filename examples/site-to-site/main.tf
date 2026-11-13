terraform {
  required_version = ">= 1.9.0, < 2.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.13.0"
    }
  }
}
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name_prefix}"
  location = var.location
  tags     = var.tags
}
resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = ["10.80.0.0/16"]
  tags                = var.tags
}
resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.80.255.0/27"]
}
resource "azurerm_public_ip" "gateway" {
  for_each            = var.active_active ? toset(["primary", "secondary"]) : toset(["primary"])
  name                = "pip-${var.name_prefix}-${each.key}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = var.tags
}
module "gateway" {
  source              = "../.."
  name                = "vgw-${var.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  type                = "Vpn"
  sku                 = "VpnGw1AZ"
  generation          = "Generation1"
  vpn_type            = "RouteBased"
  active_active       = var.active_active
  bgp_enabled         = var.bgp_enabled
  bgp_settings        = var.bgp_enabled ? { asn = 65515 } : null
  ip_configurations = {
    for key, pip in azurerm_public_ip.gateway : key => {
      name                 = "ipconfig-${key}"
      subnet_id            = azurerm_subnet.gateway.id
      public_ip_address_id = pip.id
    }
  }
  diagnostic_settings = var.log_analytics_workspace_resource_id == null ? {} : {
    central = { workspace_resource_id = var.log_analytics_workspace_resource_id }
  }
  role_assignments = var.reader_principal_id == null ? {} : {
    reader = {
      role_definition_id_or_name = "Reader"
      principal_id               = var.reader_principal_id
    }
  }
  lock = var.enable_delete_lock ? { kind = "CanNotDelete" } : null
  local_network_gateways = {
    onprem = {
      name            = "lng-${var.name_prefix}-onprem"
      gateway_address = var.onprem_public_ip
      address_space   = var.onprem_address_space
      bgp_settings = var.bgp_enabled ? {
        asn                 = var.onprem_bgp_asn
        bgp_peering_address = var.onprem_bgp_peer_ip
      } : null
    }
  }
  site_to_site_connections = {
    onprem = {
      name                      = "conn-${var.name_prefix}-onprem"
      local_network_gateway_key = "onprem"
      connection_protocol       = "IKEv2"
      bgp_enabled               = var.bgp_enabled
    }
  }
  site_to_site_shared_keys = { onprem = var.vpn_shared_key }
  tags                     = var.tags
}

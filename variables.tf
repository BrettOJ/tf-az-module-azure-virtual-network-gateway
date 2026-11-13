variable "name" {
  type        = string
  nullable    = false
  description = "Virtual network gateway name."
}
variable "location" {
  type        = string
  nullable    = false
  description = "Azure region of the gateway and its virtual network."
}
variable "resource_group_name" {
  type        = string
  nullable    = false
  description = "Existing resource group name."
}
variable "type" {
  type        = string
  default     = "Vpn"
  nullable    = false
  description = "Gateway type: Vpn or ExpressRoute."
  validation {
    condition     = contains(["Vpn", "ExpressRoute"], var.type)
    error_message = "type must be Vpn or ExpressRoute."
  }
}
variable "sku" {
  type        = string
  default     = "VpnGw1AZ"
  nullable    = false
  description = "Gateway SKU; must be available in the selected region and compatible with type and generation."
}
variable "vpn_type" {
  type        = string
  default     = "RouteBased"
  nullable    = false
  description = "RouteBased or PolicyBased. PolicyBased requires Basic."
  validation {
    condition     = contains(["RouteBased", "PolicyBased"], var.vpn_type)
    error_message = "vpn_type must be RouteBased or PolicyBased."
  }
}
variable "generation" {
  type        = string
  default     = null
  description = "Generation1, Generation2, or None. Null delegates to the provider."
  validation {
    condition     = var.generation == null ? true : contains(["Generation1", "Generation2", "None"], var.generation)
    error_message = "Invalid generation."
  }
}
variable "active_active" {
  type        = bool
  default     = false
  nullable    = false
  description = "Enable active-active VPN mode. Requires two IP configurations (three with AZ P2S)."
}
variable "ip_configurations" {
  type = map(object({
    name                 = string
    subnet_id            = string
    public_ip_address_id = optional(string)
  }))
  nullable    = false
  description = "IP configurations keyed by stable caller-defined keys. All subnets must be the same GatewaySubnet. Supply existing public IP IDs for VPN; omit for ExpressRoute."
  validation {
    condition     = length(var.ip_configurations) >= 1 && length(var.ip_configurations) <= 3
    error_message = "Supply one to three IP configurations."
  }
  validation {
    condition     = alltrue([for v in var.ip_configurations : endswith(lower(v.subnet_id), "/subnets/gatewaysubnet")])
    error_message = "Every subnet_id must reference GatewaySubnet."
  }
  validation {
    condition     = length(distinct([for v in var.ip_configurations : lower(v.subnet_id)])) == 1
    error_message = "All IP configurations must reference the same GatewaySubnet."
  }
  validation {
    condition     = length(distinct([for v in var.ip_configurations : v.name])) == length(var.ip_configurations)
    error_message = "IP configuration names must be unique."
  }
}
variable "bgp_enabled" {
  type        = bool
  default     = false
  nullable    = false
  description = "Enable BGP on the gateway. AzureRM 5.x spelling."
}
variable "bgp_settings" {
  type = object({
    asn         = optional(number, 65515)
    peer_weight = optional(number, 0)
    peering_addresses = optional(map(object({
      ip_configuration_name = string
      apipa_addresses       = optional(list(string))
    })), {})
  })
  default     = null
  description = "Optional BGP ASN, peer weight, and custom APIPA addresses."
}
variable "vpn_client_configuration" {
  type = object({
    address_space        = list(string)
    vpn_client_protocols = optional(list(string), ["OpenVPN"])
    vpn_auth_types       = list(string)
    aad_tenant           = optional(string)
    aad_audience         = optional(string)
    aad_issuer           = optional(string)
    root_certificates    = optional(map(object({ public_cert_data = string })), {})
    revoked_certificates = optional(map(object({ thumbprint = string })), {})
  })
  default     = null
  description = "Optional P2S configuration for Entra ID and/or certificate authentication. Certificate map keys are names; public_cert_data is base64 without PEM headers or newlines. RADIUS and policy groups are outside this module's scope."
  validation {
    condition     = var.vpn_client_configuration == null ? true : alltrue([for a in var.vpn_client_configuration.vpn_auth_types : contains(["AAD", "Certificate"], a)]) && length(var.vpn_client_configuration.vpn_auth_types) > 0
    error_message = "Specify AAD and/or Certificate authentication."
  }
  validation {
    condition     = var.vpn_client_configuration == null ? true : (!contains(var.vpn_client_configuration.vpn_auth_types, "AAD") || (var.vpn_client_configuration.aad_tenant != null && var.vpn_client_configuration.aad_audience != null && var.vpn_client_configuration.aad_issuer != null && toset(var.vpn_client_configuration.vpn_client_protocols) == toset(["OpenVPN"])))
    error_message = "AAD requires tenant, audience, issuer and OpenVPN as the only protocol."
  }
  validation {
    condition     = var.vpn_client_configuration == null ? true : (!contains(var.vpn_client_configuration.vpn_auth_types, "Certificate") || length(var.vpn_client_configuration.root_certificates) > 0)
    error_message = "Certificate authentication requires at least one root certificate."
  }
}
variable "custom_route_address_prefixes" {
  type        = list(string)
  default     = []
  nullable    = false
  description = "Optional custom routes advertised to P2S clients."
}
variable "default_local_network_gateway_id" {
  type        = string
  default     = null
  description = "Existing local network gateway for forced tunnelling."
}
variable "private_ip_address_enabled" {
  type        = bool
  default     = false
  nullable    = false
  description = "Enable use of the gateway private IP for supported connections. This does not create a private endpoint."
}
variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags applied to the gateway."
}
variable "timeouts" {
  type = object({
    create = optional(string, "120m")
    read   = optional(string, "5m")
    update = optional(string, "120m")
    delete = optional(string, "120m")
  })
  default     = {}
  nullable    = false
  description = "Gateway operation timeouts."
}
variable "diagnostic_settings" {
  type = map(object({
    name                                     = optional(string)
    workspace_resource_id                    = optional(string)
    storage_account_resource_id              = optional(string)
    event_hub_authorization_rule_resource_id = optional(string)
    event_hub_name                           = optional(string)
    log_categories                           = optional(set(string), [])
    log_groups                               = optional(set(string), ["allLogs"])
    metric_categories                        = optional(set(string), [])
    log_analytics_destination_type           = optional(string)
  }))
  default     = {}
  nullable    = false
  description = "Optional diagnostics to existing destinations. Category names/groups must be supported by the gateway; do not overlap categories and groups. Null destination type uses the service default."
  validation {
    condition     = alltrue([for v in var.diagnostic_settings : v.workspace_resource_id != null || v.storage_account_resource_id != null || v.event_hub_authorization_rule_resource_id != null])
    error_message = "Each diagnostic setting needs at least one destination."
  }
}
variable "role_assignments" {
  type = map(object({
    role_definition_id_or_name       = string
    principal_id                     = string
    skip_service_principal_aad_check = optional(bool, false)
    description                      = optional(string)
    condition                        = optional(string)
    condition_version                = optional(string)
  }))
  default     = {}
  nullable    = false
  description = "Gateway-scoped RBAC assignments. Role may be a built-in name or full role-definition resource ID. principal_id is the Entra object ID."
}
variable "lock" {
  type = object({
    kind = string
    name = optional(string)
  })
  default     = null
  description = "Optional CanNotDelete or ReadOnly management lock."
  validation {
    condition     = var.lock == null ? true : contains(["CanNotDelete", "ReadOnly"], var.lock.kind)
    error_message = "lock.kind must be CanNotDelete or ReadOnly."
  }
}

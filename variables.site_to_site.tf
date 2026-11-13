variable "local_network_gateways" {
  type = map(object({
    name            = string
    gateway_address = optional(string)
    gateway_fqdn    = optional(string)
    address_space   = optional(list(string), [])
    bgp_settings = optional(object({
      asn                 = number
      bgp_peering_address = string
      peer_weight         = optional(number, 0)
    }))
    tags = optional(map(string), {})
  }))
  default     = {}
  nullable    = false
  description = "Optional Azure local network gateway resources describing remote VPN devices. Keys are stable names used by site_to_site_connections. Resources use the module resource group and location."
  validation {
    condition     = alltrue([for v in var.local_network_gateways : (v.gateway_address != null) != (v.gateway_fqdn != null)])
    error_message = "Each local network gateway requires exactly one of gateway_address or gateway_fqdn."
  }
  validation {
    condition     = alltrue(flatten([for v in var.local_network_gateways : [for cidr in v.address_space : can(cidrhost(cidr, 0))]]))
    error_message = "Local network gateway address_space entries must be CIDRs."
  }
}

variable "site_to_site_connections" {
  type = map(object({
    name                               = string
    local_network_gateway_key          = optional(string)
    local_network_gateway_id           = optional(string)
    connection_protocol                = optional(string, "IKEv2")
    connection_mode                    = optional(string, "Default")
    bgp_enabled                        = optional(bool, false)
    routing_weight                     = optional(number, 10)
    dpd_timeout_seconds                = optional(number, 45)
    local_azure_ip_address_enabled     = optional(bool, false)
    use_policy_based_traffic_selectors = optional(bool, false)
    ipsec_policy = optional(object({
      dh_group         = string
      ike_encryption   = string
      ike_integrity    = string
      ipsec_encryption = string
      ipsec_integrity  = string
      pfs_group        = string
      sa_datasize      = optional(number, 102400000)
      sa_lifetime      = optional(number, 27000)
    }))
    traffic_selector_policies = optional(list(object({
      local_address_cidrs  = list(string)
      remote_address_cidrs = list(string)
    })), [])
    custom_bgp_addresses = optional(object({
      primary   = string
      secondary = optional(string)
    }))
    tags = optional(map(string), {})
  }))
  default     = {}
  nullable    = false
  description = "Optional IPsec S2S connections. Select exactly one module-created local_network_gateway_key or existing local_network_gateway_id. Shared keys are supplied separately by connection map key."
  validation {
    condition     = alltrue([for v in var.site_to_site_connections : (v.local_network_gateway_key != null) != (v.local_network_gateway_id != null)])
    error_message = "Select exactly one local_network_gateway_key or local_network_gateway_id per connection."
  }
  validation {
    condition     = alltrue([for v in var.site_to_site_connections : v.local_network_gateway_key == null ? true : contains(keys(var.local_network_gateways), v.local_network_gateway_key)])
    error_message = "local_network_gateway_key must exist in local_network_gateways."
  }
  validation {
    condition     = alltrue([for v in var.site_to_site_connections : contains(["IKEv1", "IKEv2"], v.connection_protocol) && contains(["Default", "InitiatorOnly", "ResponderOnly"], v.connection_mode)])
    error_message = "Use IKEv1/IKEv2 and Default/InitiatorOnly/ResponderOnly."
  }
  validation {
    condition     = alltrue([for v in var.site_to_site_connections : !v.use_policy_based_traffic_selectors || v.ipsec_policy != null])
    error_message = "Policy-based traffic selectors require an explicit ipsec_policy."
  }
}

variable "site_to_site_shared_keys" {
  type        = map(string)
  default     = {}
  nullable    = false
  sensitive   = true
  description = "Pre-shared keys keyed by site_to_site_connections map key. Supply through secret variables or a secret store. Values remain in Terraform state; protect the backend."
}

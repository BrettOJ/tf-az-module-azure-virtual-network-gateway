variable "subscription_id" {
  type        = string
  description = "Target Azure subscription ID."
}
variable "location" {
  type        = string
  default     = "southeastasia"
  description = "Azure region supporting the selected AZ gateway and public IPs."
}
variable "name_prefix" {
  type        = string
  default     = "vpn-dev-sea-001"
  description = "Resource naming prefix."
}
variable "active_active" {
  type        = bool
  default     = false
  description = "Create a second public IP and active-active gateway."
}
variable "bgp_enabled" {
  type        = bool
  default     = false
  description = "Enable BGP using ASN 65515."
}
variable "log_analytics_workspace_resource_id" {
  type        = string
  default     = null
  description = "Existing Log Analytics workspace ID; null disables diagnostics."
}
variable "reader_principal_id" {
  type        = string
  default     = null
  description = "Optional Entra object ID to grant Reader on the gateway."
}
variable "enable_delete_lock" {
  type        = bool
  default     = false
  description = "Create a CanNotDelete lock."
}
variable "tags" {
  type        = map(string)
  default     = { environment = "dev", managed_by = "terraform" }
  description = "Resource tags."
}

variable "onprem_public_ip" {
  type        = string
  description = "Real public IPv4 address of the on-premises VPN device."
}
variable "onprem_address_space" {
  type        = list(string)
  description = "Remote network CIDRs. Must not overlap with Azure or P2S pools."
}
variable "vpn_shared_key" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Pre-shared key matching the on-premises VPN device. Inject through a secret variable."
  validation {
    condition     = length(trimspace(var.vpn_shared_key)) > 0
    error_message = "vpn_shared_key cannot be empty."
  }
}
variable "onprem_bgp_asn" {
  type        = number
  default     = null
  description = "Remote device ASN, required when bgp_enabled is true."
  validation {
    condition     = !var.bgp_enabled || var.onprem_bgp_asn != null
    error_message = "Set onprem_bgp_asn when enabling BGP."
  }
}
variable "onprem_bgp_peer_ip" {
  type        = string
  default     = null
  description = "Remote device BGP peer IP, required when bgp_enabled is true."
  validation {
    condition     = !var.bgp_enabled || var.onprem_bgp_peer_ip != null
    error_message = "Set onprem_bgp_peer_ip when enabling BGP."
  }
}

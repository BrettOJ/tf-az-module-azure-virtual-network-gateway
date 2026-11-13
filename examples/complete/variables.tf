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

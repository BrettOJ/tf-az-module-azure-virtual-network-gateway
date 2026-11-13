resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each                       = var.diagnostic_settings
  name                           = coalesce(each.value.name, "diag-${var.name}-${each.key}")
  target_resource_id             = azurerm_virtual_network_gateway.this.id
  log_analytics_workspace_id     = each.value.workspace_resource_id
  storage_account_id             = each.value.storage_account_resource_id
  eventhub_authorization_rule_id = each.value.event_hub_authorization_rule_resource_id
  eventhub_name                  = each.value.event_hub_name
  log_analytics_destination_type = each.value.log_analytics_destination_type
  dynamic "enabled_log" {
    for_each = each.value.log_categories
    content { category = enabled_log.value }
  }
  dynamic "enabled_log" {
    for_each = each.value.log_groups
    content { category_group = enabled_log.value }
  }
  dynamic "enabled_metric" {
    for_each = each.value.metric_categories
    content { category = enabled_metric.value }
  }
}
resource "azurerm_role_assignment" "this" {
  for_each                         = var.role_assignments
  scope                            = azurerm_virtual_network_gateway.this.id
  principal_id                     = each.value.principal_id
  role_definition_id               = startswith(each.value.role_definition_id_or_name, "/") ? each.value.role_definition_id_or_name : null
  role_definition_name             = startswith(each.value.role_definition_id_or_name, "/") ? null : each.value.role_definition_id_or_name
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
  description                      = each.value.description
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
}
resource "azurerm_management_lock" "this" {
  count      = var.lock == null ? 0 : 1
  name       = coalesce(var.lock.name, "lock-${var.name}")
  scope      = azurerm_virtual_network_gateway.this.id
  lock_level = var.lock.kind
  notes      = "Managed by Terraform."
  depends_on = [azurerm_monitor_diagnostic_setting.this, azurerm_role_assignment.this, azurerm_virtual_network_gateway_connection.this]
}

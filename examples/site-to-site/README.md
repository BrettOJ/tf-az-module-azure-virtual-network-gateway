# Site-to-site VPN example

See the Site-to-site VPN section of [the module README](../../README.md) for setup, secret injection, BGP options and remote device configuration. Copy terraform.tfvars.example to terraform.tfvars, replace the documentation-only remote public IP, and supply TF_VAR_vpn_shared_key securely.

This example creates the Azure resources only. Configure your on-premises VPN device separately with the same pre-shared key and matching IKE/IPsec settings.

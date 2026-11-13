# Terraform Azure Virtual Network Gateway module

Custom AVM-style resource module using azurerm_virtual_network_gateway. This is not an official Azure Verified Module and does not claim full AVM conformance. It uses typed inputs, stable map keys, separate resource/extension/output files, no embedded provider configuration, and optional diagnostics, RBAC, management locks, local network gateways and site-to-site IPsec connections. No telemetry is collected.

## Requirements

- Terraform >= 1.9.0 and < 2.0.0.
- AzureRM >= 5.13.0 and < 6.0.0. The complete example pins ~> 5.13.0 and includes its dependency lock file.
- An Azure subscription, authenticated deployment identity, and permission to create the selected resources. Creating role assignments additionally requires role-assignment write permission.
- Existing resource group, GatewaySubnet, and (for VPN) public IPs when using the module directly. The complete example creates these dependencies.

This module deliberately targets AzureRM 5.x and uses bgp_enabled. Do not simply lower the version constraint for a root configuration still using AzureRM 4.x; provider arguments and behavior must be reviewed. All modules in a Terraform root must agree on compatible provider constraints.

## Quick start (PowerShell)

Extract the archive, then:

~~~powershell
cd terraform-azurerm-virtual-network-gateway/examples/complete
Copy-Item terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: replace the subscription ID and review region, names and CIDRs.
az login
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
~~~

The example defaults to Southeast Asia, VpnGw1AZ / Generation1, route-based active-standby VPN, Standard Static zone-redundant public IP, a 10.80.0.0/16 VNet and 10.80.255.0/27 GatewaySubnet. Confirm SKU/zone availability and non-overlapping CIDRs for your environment. Gateway provisioning can take 30–60 minutes or longer; module create/update/delete timeouts default to 120 minutes.

Set active_active = true to create a second public IP and second gateway IP configuration. Set bgp_enabled = true to configure ASN 65515. The example has no P2S configuration; adding AZ active-active P2S also requires a third public IP and IP configuration.

Optionally set log_analytics_workspace_resource_id, reader_principal_id and enable_delete_lock to enable the extension resources. These reference existing workspace and principal objects. Diagnostics default to allLogs with metrics disabled; select supported categories/groups for your gateway when overriding.

## Using an existing network

~~~hcl
module "gateway" {
  source = "./modules/terraform-azurerm-virtual-network-gateway"

  name                = "vgw-hub-sea-001"
  location            = "southeastasia"
  resource_group_name = "rg-network-sea-001"
  type                = "Vpn"
  sku                 = "VpnGw1AZ"
  generation          = "Generation1"

  ip_configurations = {
    primary = {
      name                 = "ipconfig-primary"
      subnet_id            = azurerm_subnet.gateway.id
      public_ip_address_id = azurerm_public_ip.gateway.id
    }
  }
  tags = { environment = "production" }
}
~~~

Place the extracted module under the source path shown, or change source to its actual relative location. Declare the azurerm provider and authentication in your calling root module. The subnet and public IP references above must exist in that root or be replaced with resource IDs/data-source outputs.

## Site-to-site VPN

Two optional maps create the Azure resources for remote sites:

| Resource | Input | Purpose |
|---|---|---|
| azurerm_local_network_gateway | local_network_gateways | Describes the remote VPN device public IP/FQDN, network CIDRs and optional BGP peer |
| azurerm_virtual_network_gateway_connection | site_to_site_connections | Creates an IPsec connection from this module's VPN gateway to a local network gateway |
| Sensitive input (no resource) | site_to_site_shared_keys | Supplies matching pre-shared keys, indexed by connection key |

All maps default to empty, preserving the original gateway-only behavior. Multiple map entries support multiple sites. Local gateway resources and connections use the module's resource group/location. Per-item tags override matching common tags. Stable map keys are Terraform resource identities; renaming them requires a moved block or state migration to avoid replacement.

### Complete S2S example

Use examples/site-to-site. It creates the resource group, VNet, GatewaySubnet, public IP(s), Azure VPN gateway, local network gateway and IKEv2 IPsec connection. Its default is static routing with BGP disabled.

~~~powershell
cd terraform-azurerm-virtual-network-gateway/examples/site-to-site
Copy-Item terraform.tfvars.example terraform.tfvars
# Edit subscription ID, onprem_public_ip and onprem_address_space.
# The 203.0.113.10 example address is documentation-only and MUST be replaced.
$env:TF_VAR_vpn_shared_key = [System.Net.NetworkCredential]::new("", (Read-Host "VPN pre-shared key" -AsSecureString)).Password
az login
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
Remove-Item Env:TF_VAR_vpn_shared_key
~~~

In CI/CD, map a secret pipeline variable to TF_VAR_vpn_shared_key instead of prompting. The exact same key must be configured on the remote device. Sensitive markings hide normal console output but do not remove secrets from state or saved plan files; secure both. No PSK is included in the example variables file or outputs.

For BGP, set bgp_enabled = true and supply onprem_bgp_asn and onprem_bgp_peer_ip. The example configures BGP on the Azure gateway, remote-site representation and connection together. Azure's example ASN is 65515; use a suitable different ASN for the remote peer. For static routing, onprem_address_space must contain the networks behind the remote device.

### Add sites to an existing module call

~~~hcl
local_network_gateways = {
  branch = {
    name            = "lng-branch-001"
    gateway_address = "203.0.113.10" # REPLACE with remote device public IP
    address_space   = ["192.168.10.0/24"]
  }
}
site_to_site_connections = {
  branch_tunnel = {
    name                      = "conn-branch-001"
    local_network_gateway_key = "branch"
    connection_protocol       = "IKEv2"
  }
}
site_to_site_shared_keys = {
  branch_tunnel = var.branch_vpn_shared_key
}
~~~

Declare branch_vpn_shared_key in the calling root as type = string and sensitive = true, without a hard-coded secret default. Connection keys and local gateway keys may differ: local_network_gateway_key links them, and the shared-key map is indexed by the CONNECTION key.

To connect to an existing local network gateway, set local_network_gateway_id to its full Azure resource ID instead of local_network_gateway_key, and omit that site from local_network_gateways. Set exactly one of the two references. For an existing gateway, verify its remote address ranges and BGP configuration yourself; the module cannot validate those external properties. A local network gateway may also be created without a connection by populating only local_network_gateways.

### Optional connection settings

Each connection exposes connection_protocol, connection_mode, bgp_enabled, routing_weight, dpd_timeout_seconds, local_azure_ip_address_enabled, custom_bgp_addresses, use_policy_based_traffic_selectors, ipsec_policy and traffic_selector_policies. Full structures are in variables.site_to_site.tf. Omit ipsec_policy to use Azure's default policy set. To agree a custom policy with your network team, add for example:

~~~hcl
ipsec_policy = {
  dh_group         = "DHGroup14"
  ike_encryption   = "AES256"
  ike_integrity    = "SHA256"
  ipsec_encryption = "AES256"
  ipsec_integrity  = "SHA256"
  pfs_group        = "PFS14"
  sa_lifetime     = 27000
  sa_datasize     = 102400000
}
~~~

Use this only if the remote device supports the matching settings. Enabling use_policy_based_traffic_selectors requires an explicit ipsec_policy. In traffic_selector_policies, local_address_cidrs are the Azure networks and remote_address_cidrs are the on-premises networks. These connection traffic selectors do not change the gateway's vpn_type. custom_bgp_addresses requires active-active mode and BGP; local_azure_ip_address_enabled requires private_ip_address_enabled on the Azure gateway and appropriate private connectivity. New resources use the provider's default timeouts (30m create/update/delete and 5m read); the existing timeouts input controls only the Azure virtual network gateway.

### Configure and verify the remote device

1. Use the example output public_ip_addresses as the Azure VPN peer endpoint(s). In active-active mode, configure tunnels to both Azure public IPs on the remote device.
2. Match IKE version, PSK and any custom IPsec policy. Permit the required VPN traffic through intervening firewalls (including UDP 500/4500 and ESP as applicable).
3. Configure non-overlapping network ranges and routes in both directions, or establish the BGP sessions using the output Azure BGP addresses and your remote peer settings.
4. Check Azure Portal > Virtual network gateway > Connections for Connected status, then test traffic and routes from both sides. Creating Azure resources alone does not configure the remote device or prove tunnel connectivity.

## Supported configuration

| Input | Default / purpose |
|---|---|
| name, location, resource_group_name | Required gateway name, region and existing resource group |
| ip_configurations | Required map of name, subnet_id, optional public_ip_address_id |
| type | Vpn; also accepts ExpressRoute |
| sku | VpnGw1AZ; select a SKU appropriate to type/generation |
| vpn_type | RouteBased; PolicyBased is restricted to Basic |
| generation | null (provider default); example explicitly uses Generation1 |
| active_active | false |
| bgp_enabled / bgp_settings | false / null; ASN, peer weight, optional custom APIPA addresses |
| vpn_client_configuration | null; optional Entra ID and/or certificate P2S authentication |
| custom_route_address_prefixes | Empty; optional P2S advertised routes |
| default_local_network_gateway_id | null; optional forced-tunnelling default gateway |
| private_ip_address_enabled | false; use private gateway IP where supported |
| diagnostic_settings | Empty map; existing workspace, storage or Event Hub destinations |
| role_assignments | Empty map; gateway-scoped RBAC by role name or full role-definition ID |
| lock | null; optional CanNotDelete or ReadOnly |
| tags | Empty map |
| timeouts | Gateway create/update/delete 120m; read 5m |
| local_network_gateways | Empty map; optional remote-site representations |
| site_to_site_connections | Empty map; optional IPsec connections to new or existing local gateways |
| site_to_site_shared_keys | Empty sensitive map; one PSK per connection key |

Full typed structures and descriptions are in variables.tf. Outputs are resource_id, name, bgp_settings, ip_configuration, local_network_gateway_resource_ids and site_to_site_connection_resource_ids. The example additionally exposes assigned public IP addresses.

### P2S Entra ID configuration

Add this object to a VPN module call, using tenant-specific endpoints and the audience for your Azure VPN Client configuration:

~~~hcl
vpn_client_configuration = {
  address_space        = ["172.20.240.0/24"]
  vpn_client_protocols = ["OpenVPN"]
  vpn_auth_types       = ["AAD"]
  aad_tenant          = "https://login.microsoftonline.com/YOUR-TENANT-ID/"
  aad_issuer          = "https://sts.windows.net/YOUR-TENANT-ID/"
  aad_audience        = "YOUR-AZURE-VPN-APPLICATION-AUDIENCE"
}
~~~

The VPN client pool must not overlap with connected networks. Client application consent and client profile distribution are configured separately. For Certificate authentication, provide root_certificates = { root = { public_cert_data = "BASE64-CERTIFICATE-BODY" } }; omit PEM headers and newlines. This is a public certificate, never a private key.

### ExpressRoute

Set type = "ExpressRoute", sku to a compatible SKU such as "ErGw1AZ", generation = "None", active_active = false, and provide a single IP configuration with subnet_id and name only. AzureRM 5.13 documentation says to omit public_ip_address_id for ExpressRoute. The supplied complete example is VPN-specific and should not be changed to ExpressRoute without also removing its public IP resources and adapting the module call. ErGwScale scale-unit options are outside this module's scope.

## Operational notes and scope

- Use a subnet named exactly GatewaySubnet, /27 or larger for the example's gateway. Do not associate an NSG or a default 0.0.0.0/0 UDR with GatewaySubnet. The module fixes private IP allocation to Dynamic, as required by the resource.
- Optional local_network_gateways and site_to_site_connections create the Azure side of S2S IPsec tunnels. The on-premises VPN device must be configured separately. ExpressRoute circuit connections remain outside scope.
- Standard public IPs for VPN must match the gateway's region and availability-zone requirements. Region, SKU, generation, and protocol compatibility remain subject to Azure validation.
- The gateway management lock is created after diagnostics, RBAC and S2S connections. This gateway-scoped lock does not protect the separate local network gateway or connection resources. To maintain a ReadOnly-locked gateway, first apply lock = null, perform updates, then reapply the lock. Terraform can remove a managed lock during destroy if the caller has permission; ancestor locks can still block changes.
- The reusable module does not create subnets, public IPs or workspaces. Their lifecycle stays with the caller. Both examples own their network and public IP dependencies. Local network gateways and S2S connections are created only when their input maps contain entries.
- RADIUS, P2S policy groups/custom IPsec policies, NAT rules, ExpressRoute/VNet-to-VNet connections and ErGwScale tuning are not implemented by this module.
- Use an appropriately secured remote state backend for production. Review plans for replacements, especially IP-configuration changes. No resources were deployed as part of creating this package.

## Import an existing gateway

From the calling root (adapt the module label and resource ID):

~~~powershell
terraform import 'module.gateway.azurerm_virtual_network_gateway.this' '/subscriptions/SUBSCRIPTION-ID/resourceGroups/RG-NAME/providers/Microsoft.Network/virtualNetworkGateways/GATEWAY-NAME'
terraform plan
~~~

Configure inputs to match the existing gateway before importing. Importing the gateway does not import separately managed public IPs or extension resources.

## Validation

Validated with Terraform 1.12.2 and AzureRM 5.13.0:

- terraform fmt -recursive and format check.
- terraform init -backend=false and terraform validate for the reusable module.
- terraform init -backend=false and terraform validate for examples/complete and examples/site-to-site.
- terraform test: six mocked plan tests passed (gateway-only compatibility, managed site/custom policy, existing site, BGP/FQDN, missing PSK rejection and conflicting references rejection).

Validation checks Terraform configuration and provider schemas; no authenticated Azure plan/apply or live connectivity test was performed.

## Sources reviewed (13 November 2026)

- [AzureRM 5.13 gateway resource](https://registry.terraform.io/providers/hashicorp/azurerm/5.13.0/docs/resources/virtual_network_gateway)
- [Versioned provider documentation source](https://github.com/hashicorp/terraform-provider-azurerm/blob/v5.13.0/website/docs/r/virtual_network_gateway.html.markdown)
- [AVM resource-module conventions](https://azure.github.io/Azure-Verified-Modules/specs/tf/res/)
- [AVM Terraform specifications](https://azure.github.io/Azure-Verified-Modules/specs/tf/)
- [Microsoft VPN gateway configuration](https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-about-vpn-gateway-settings)

Current AVM requirements differ from this custom AzureRM-based module, including requirements for AzAPI. This package follows selected AVM organizational and interface conventions while retaining the azurerm_virtual_network_gateway resource requested.

Additional resource documentation:

- [Local network gateway, AzureRM 5.13](https://registry.terraform.io/providers/hashicorp/azurerm/5.13.0/docs/resources/local_network_gateway)
- [Gateway connection, AzureRM 5.13](https://registry.terraform.io/providers/hashicorp/azurerm/5.13.0/docs/resources/virtual_network_gateway_connection)

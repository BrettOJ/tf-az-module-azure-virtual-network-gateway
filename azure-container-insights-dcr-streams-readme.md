# Azure Container Insights DCR Stream Configuration

## Overview

When a Container Insights Data Collection Rule (DCR) uses:

```hcl
streams = [
  "Microsoft-ContainerInsights-Group-Default"
]
```

Azure treats `Microsoft-ContainerInsights-Group-Default` as a shorthand for collecting the standard Container Insights data streams into the configured Log Analytics workspace.

This is convenient, but it can create significant Log Analytics ingestion volume because it includes performance, inventory, Kubernetes event, and container log data.

For environments that already use **Azure Monitor Managed Prometheus** and **Managed Grafana**, Microsoft recommends using the **Logs and events** collection set rather than collecting the full Container Insights dataset into Log Analytics.

---

## Streams included by the default group

The standard Container Insights streams and their corresponding Log Analytics tables are:

| DCR stream | Log Analytics table | Purpose |
|---|---|---|
| `Microsoft-ContainerInventory` | `ContainerInventory` | Container inventory and state |
| `Microsoft-ContainerLog` | `ContainerLog` | Legacy container stdout/stderr logs |
| `Microsoft-ContainerLogV2` | `ContainerLogV2` | Current container stdout/stderr logs |
| `Microsoft-ContainerNodeInventory` | `ContainerNodeInventory` | Container/node association data |
| `Microsoft-InsightsMetrics` | `InsightsMetrics` | Container Insights metrics |
| `Microsoft-KubeEvents` | `KubeEvents` | Kubernetes events |
| `Microsoft-KubeMonAgentEvents` | `KubeMonAgentEvents` | Azure Monitor agent events |
| `Microsoft-KubeNodeInventory` | `KubeNodeInventory` | Kubernetes node inventory |
| `Microsoft-KubePodInventory` | `KubePodInventory` | Kubernetes pod/container inventory |
| `Microsoft-KubePVInventory` | `KubePVInventory` | Kubernetes persistent volume inventory |
| `Microsoft-KubeServices` | `KubeServices` | Kubernetes service inventory |
| `Microsoft-Perf` | `Perf` | CPU, memory, and other performance counters |

Azure also supports:

```text
Microsoft-ContainerLogV2-HighScale
```

for the high-scale ContainerLogV2 collection mode. Do **not** configure both the normal `Microsoft-ContainerLogV2` and `Microsoft-ContainerLogV2-HighScale` streams together because that can result in duplicate data.

---

## Effect of `enableContainerLogV2`

If the DCR contains:

```hcl
extension_json = jsonencode({
  dataCollectionSettings = {
    enableContainerLogV2 = true
  }
})
```

container stdout/stderr logs are written to:

```text
ContainerLogV2
```

instead of the legacy:

```text
ContainerLog
```

The setting controls which container log schema/table is used. It does not by itself disable container log collection.

---

## Why the default group can create high LAW ingestion

Using:

```hcl
streams = [
  "Microsoft-ContainerInsights-Group-Default"
]
```

means the Log Analytics workspace receives a broad Container Insights dataset, conceptually including:

```text
ContainerLogV2
ContainerInventory
ContainerNodeInventory
KubePodInventory
KubeNodeInventory
KubePVInventory
KubeServices
KubeEvents
KubeMonAgentEvents
Perf
InsightsMetrics
```

For a multi-cluster environment, `Perf`, `InsightsMetrics`, inventories, and high-volume `ContainerLogV2` data can contribute significantly to Log Analytics ingestion.

---

# Recommended configuration when using Managed Prometheus

If the environment already uses:

```text
Microsoft.AzureMonitor.Containers.Metrics
        |
        v
Azure Monitor Workspace
        |
        v
Managed Prometheus
        |
        v
Managed Grafana
```

then CPU, memory, Kubernetes, node, pod, and container metrics can be collected through Managed Prometheus instead of duplicating much of that performance data into Log Analytics.

Microsoft's **Logs and events** grouping consists of:

```text
ContainerLog / ContainerLogV2
KubeEvents
KubePodInventory
```

and is recommended when Managed Prometheus is enabled.

Instead of the default group:

```hcl
streams = [
  "Microsoft-ContainerInsights-Group-Default"
]
```

use explicit streams:

```hcl
streams = [
  "Microsoft-ContainerLogV2",
  "Microsoft-KubeEvents",
  "Microsoft-KubePodInventory"
]
```

The same stream list should be used in the DCR `data_flow`:

```hcl
data_flow {
  streams = [
    "Microsoft-ContainerLogV2",
    "Microsoft-KubeEvents",
    "Microsoft-KubePodInventory"
  ]

  destinations = [
    "ciworkspace"
  ]
}
```

---

## Example Terraform DCR

```hcl
resource "azurerm_monitor_data_collection_rule" "container_insights" {
  name                = "dcr-container-insights"
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = "Linux"

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.law.id
      name                  = "ciworkspace"
    }
  }

  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      extension_name = "ContainerInsights"

      streams = [
        "Microsoft-ContainerLogV2",
        "Microsoft-KubeEvents",
        "Microsoft-KubePodInventory"
      ]

      extension_json = jsonencode({
        dataCollectionSettings = {
          interval               = "1m"
          namespaceFilteringMode = "Off"
          enableContainerLogV2   = true
        }
      })
    }
  }

  data_flow {
    streams = [
      "Microsoft-ContainerLogV2",
      "Microsoft-KubeEvents",
      "Microsoft-KubePodInventory"
    ]

    destinations = [
      "ciworkspace"
    ]
  }
}
```

---

## What this removes from Log Analytics

By replacing the default group with the three explicit streams above, the DCR no longer requests these streams:

```text
Microsoft-Perf
Microsoft-InsightsMetrics
Microsoft-ContainerInventory
Microsoft-ContainerNodeInventory
Microsoft-KubeNodeInventory
Microsoft-KubePVInventory
Microsoft-KubeServices
Microsoft-KubeMonAgentEvents
```

The most important cost reduction for an environment already using Managed Prometheus is normally the removal of:

```text
Microsoft-Perf
Microsoft-InsightsMetrics
```

because performance metrics are then handled by the Azure Monitor workspace rather than duplicated into Log Analytics.

---

## Resulting monitoring architecture

```text
                         Kubernetes clusters
                                |
                +---------------+----------------+
                |                                |
                v                                v
      Container Insights                 Managed Prometheus
      / AMA Logs                          Metrics extension
                |                                |
                v                                v
     Log Analytics Workspace            Azure Monitor Workspace
                |                                |
       ContainerLogV2                           |
       KubeEvents                               v
       KubePodInventory                  Managed Grafana
```

### Log Analytics

Use Log Analytics primarily for:

```text
ContainerLogV2
KubeEvents
KubePodInventory
```

### Azure Monitor Workspace / Managed Prometheus

Use Managed Prometheus for:

```text
Node CPU
Node memory
Pod CPU
Pod memory
Container CPU
Container memory
Kubernetes metrics
Prometheus application metrics
Alerting metrics
```

---

# Namespace exclusions for ContainerLogV2

The DCR `namespaceFilteringMode` does **not** provide the primary namespace filtering mechanism for container stdout/stderr logs written to `ContainerLogV2`.

To exclude noisy infrastructure namespaces such as Dynatrace, Aqua Security, or Geneos Netprobe from `ContainerLogV2`, use the AMA logs ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: container-azm-ms-agentconfig
  namespace: kube-system

data:
  config-version: "ver1"

  log-data-collection-settings: |-
    [log_collection_settings]

      [log_collection_settings.stdout]
        enabled = true
        exclude_namespaces = [
          "dynatrace",
          "aqua",
          "geneos-netprobe"
        ]

      [log_collection_settings.stderr]
        enabled = true
        exclude_namespaces = [
          "dynatrace",
          "aqua",
          "geneos-netprobe"
        ]
```

Use the exact namespace names deployed in each cluster.

---

# Validate Log Analytics ingestion

After changing the DCR, use this query to monitor the affected tables:

```kusto
Usage
| where TimeGenerated > ago(24h)
| where IsBillable == true
| where DataType in (
    "Perf",
    "InsightsMetrics",
    "ContainerLogV2",
    "KubeEvents",
    "KubePodInventory"
)
| summarize
    GB = round(sum(Quantity) / 1000.0, 3)
    by bin(TimeGenerated, 1h), DataType
| order by TimeGenerated asc
```

After the new DCR configuration has propagated, ingestion into `Perf` and `InsightsMetrics` should fall significantly or stop if no other DCR or data source is sending data to those tables.

To identify the highest-volume container log namespaces:

```kusto
ContainerLogV2
| where TimeGenerated > ago(24h)
| where _IsBillable == "true"
| summarize
    Records = count(),
    IngestedGB = round(sum(_BilledSize) / 1024 / 1024 / 1024, 3)
    by PodNamespace
| order by IngestedGB desc
```

---

# Important considerations

1. Removing `Perf` and `InsightsMetrics` can affect the classic/default Container Insights performance views in the Azure portal.
2. If Managed Prometheus and Managed Grafana are the primary performance-monitoring solution, this is usually an acceptable trade-off.
3. `Microsoft-ContainerInsights-Group-Default` is convenient but provides less control over Log Analytics ingestion.
4. Prefer explicitly listing only the streams actually required.
5. Keep `ContainerLogV2` rather than the legacy `ContainerLog` schema.
6. Do not configure `Microsoft-ContainerLogV2` and `Microsoft-ContainerLogV2-HighScale` simultaneously.
7. Namespace exclusion for container stdout/stderr should be managed separately through `container-azm-ms-agentconfig`.

---

## Microsoft documentation

- Enable monitoring for Arc-enabled Kubernetes clusters:  
  https://learn.microsoft.com/azure/azure-monitor/containers/kubernetes-monitoring-enable-arc

- Enable monitoring for AKS / Container Insights stream values:  
  https://learn.microsoft.com/azure/azure-monitor/containers/kubernetes-monitoring-enable

- Advanced filtering and transformations for Kubernetes logs:  
  https://learn.microsoft.com/azure/azure-monitor/containers/container-insights-transformations

- Configure the ContainerLogV2 schema:  
  https://learn.microsoft.com/azure/azure-monitor/containers/container-insights-logs-schema

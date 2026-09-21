# Edge PoP Monitoring

## Overview

Система мониторинга Edge PoP узлов CloudBridge Relay обеспечивает полную наблюдаемость за производительностью, доступностью и безопасностью инфраструктуры.

## Architecture

```mermaid
graph TB
    subgraph "Edge PoP Nodes"
        M[ Moscow PoP<br/>Metrics: 9091<br/>Health: /health<br/>MASQUE: 9090]
        F[ Frankfurt PoP<br/>Metrics: 9091<br/>Health: /health<br/>MASQUE: 9090]
        A[ Amsterdam PoP<br/>Metrics: 9091<br/>Health: /health<br/>MASQUE: 9090]
    end

    subgraph "Monitoring Stack"
        P[Prometheus<br/>Scrape: 15s<br/>Retention: 30d<br/>Rules: edge-pops-alerts]
        AM[Alertmanager<br/>Routes: critical/warning<br/>Receivers: email/slack<br/>Grouping: alertname,region]
        G[Grafana<br/>Dashboards: Edge PoP<br/>Panels: RTT, Handover, P2P<br/>Alerts: Visual]
    end

    M -->|Metrics| P
    F -->|Metrics| P
    A -->|Metrics| P

    P -->|Alerts| AM
    AM -->|Notifications| G

    P -->|Data| G
```

## Key Metrics

### Core Performance Metrics

| Metric | Description | SLO Target | Alert Threshold |
|--------|-------------|------------|-----------------|
| `relay_rtt_seconds` | RTT между PoP узлами | p95 < 50ms | > 50ms for 5m |
| `relay_handover_duration_seconds` | Время handover между PoP | p95 < 300ms | > 300ms for 2m |
| `relay_p2p_percentage` | Процент P2P соединений | ≥ 60% | < 60% for 10m |
| `relay_error_rate` | Частота ошибок | < 1% | > 1% for 5m |
| `relay_throughput_bytes` | Пропускная способность | > 1Gbps | < 1Gbps for 10m |

### MASQUE Metrics

| Metric | Description | SLO Target | Alert Threshold |
|--------|-------------|------------|-----------------|
| `masque_active_contexts` | Активные MASQUE контексты | < 80% от max | > 80% for 5m |
| `masque_connections_total` | Общее количество соединений | - | - |
| `masque_errors_total` | Количество ошибок MASQUE | < 1% | > 1% for 5m |
| `masque_neighbor_connectivity` | Связность с соседями | = 1 | = 0 for 2m |
| `masque_rtt_seconds` | RTT через MASQUE | p95 < 50ms | > 50ms for 5m |

### System Metrics

| Metric | Description | SLO Target | Alert Threshold |
|--------|-------------|------------|-----------------|
| `up` | Доступность PoP узлов | = 1 | = 0 for 1m |
| `relay_cpu_usage_percent` | Использование CPU | < 80% | > 80% for 10m |
| `relay_memory_usage_percent` | Использование памяти | < 80% | > 80% for 10m |
| `relay_disk_usage_percent` | Использование диска | < 80% | > 80% for 10m |

## Prometheus Configuration

### Scrape Configuration

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'cloudbridge-edge-pops'
    environment: 'production'

scrape_configs:
- job_name: 'edge-pops'
  static_configs:
    - targets:
      - 'relay-mow:9091'
      - 'relay-fra:9091'
      - 'relay-ams:9091'
  relabel_configs:
    - source_labels: [__address__]
      regex: '(.*):(.*)'
      target_label: region
      replacement: "${1}"
    - source_labels: [__address__]
      regex: 'relay-(.*):.*'
      target_label: pop
      replacement: "${1}"
  metric_relabel_configs:
    - source_labels: [__name__]
      regex: 'relay_.*'
      action: keep
```

### Recording Rules

```yaml
groups:
- name: edge-pops-recording
  rules:
  - record: relay_rtt_seconds_p95
    expr: histogram_quantile(0.95, rate(relay_rtt_seconds_bucket[5m]))
  - record: relay_handover_duration_seconds_p95
    expr: histogram_quantile(0.95, rate(relay_handover_duration_seconds_bucket[5m]))
  - record: relay_p2p_percentage_avg
    expr: avg_over_time(relay_p2p_percentage[5m])
  - record: relay_error_rate_avg
    expr: rate(relay_errors_total[5m]) / rate(relay_requests_total[5m])
```

## Alerting Rules

### Critical Alerts

```yaml
groups:
- name: edge-pops-critical
  rules:
  - alert: PoPDown
    expr: up{job="edge-pops"} == 0
    for: 1m
    labels:
      severity: critical
      service: edge-pops
    annotations:
      summary: "PoP узел недоступен"
      description: "PoP узел {{ $labels.instance }} недоступен"
      runbook_url: "https://docs.2gc.ru/runbooks/pop-down"

  - alert: HandoverTimeout
    expr: relay_handover_duration_seconds > 0.3
    for: 2m
    labels:
      severity: critical
      service: edge-pops
    annotations:
      summary: "Handover превысил 300ms"
      description: "Handover для региона {{ $labels.region }} составляет {{ $value }}s"
      runbook_url: "https://docs.2gc.ru/runbooks/handover-timeout"

  - alert: HighErrorRate
    expr: relay_error_rate > 0.01
    for: 5m
    labels:
      severity: critical
      service: edge-pops
    annotations:
      summary: "Высокая частота ошибок"
      description: "Error rate для региона {{ $labels.region }} составляет {{ $value }}"
      runbook_url: "https://docs.2gc.ru/runbooks/high-error-rate"
```

### Warning Alerts

```yaml
groups:
- name: edge-pops-warning
  rules:
  - alert: HighRTT
    expr: relay_rtt_seconds{region=~"mow|fra|ams"} > 0.05
    for: 5m
    labels:
      severity: warning
      service: edge-pops
    annotations:
      summary: "RTT между PoP превысил 50ms"
      description: "RTT для региона {{ $labels.region }} составляет {{ $value }}s"
      runbook_url: "https://docs.2gc.ru/runbooks/high-rtt"

  - alert: LowP2PRatio
    expr: relay_p2p_percentage < 60
    for: 10m
    labels:
      severity: warning
      service: edge-pops
    annotations:
      summary: "P2P соединения ниже 60%"
      description: "P2P процент для региона {{ $labels.region }} составляет {{ $value }}%"
      runbook_url: "https://docs.2gc.ru/runbooks/low-p2p-ratio"

  - alert: LowThroughput
    expr: relay_throughput_bytes < 1000000000
    for: 10m
    labels:
      severity: warning
      service: edge-pops
    annotations:
      summary: "Низкая пропускная способность"
      description: "Throughput для региона {{ $labels.region }} составляет {{ $value }} bytes/s"
      runbook_url: "https://docs.2gc.ru/runbooks/low-throughput"
```

## Alertmanager Configuration

### Routing Rules

```yaml
route:
  group_by: ['alertname', 'region', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'web.hook'
  routes:
  - match:
      severity: critical
    receiver: 'critical-alerts'
    group_wait: 5s
    repeat_interval: 30m
  - match:
      severity: warning
    receiver: 'warning-alerts'
    group_wait: 30s
    repeat_interval: 2h
```

### Notification Receivers

```yaml
receivers:
- name: 'critical-alerts'
  email_configs:
  - to: 'ops@2gc.ru'
    subject: '[CRITICAL] CloudBridge Edge PoP Alert'
    body: |
      {{ range .Alerts }}
      Alert: {{ .Annotations.summary }}
      Description: {{ .Annotations.description }}
      Region: {{ .Labels.region }}
      Service: {{ .Labels.service }}
      Runbook: {{ .Annotations.runbook_url }}
      {{ end }}
  slack_configs:
  - api_url: 'https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX'
    channel: '#cloudbridge-alerts'
    title: 'CloudBridge Critical Alert'
    text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'

- name: 'warning-alerts'
  email_configs:
  - to: 'team@2gc.ru'
    subject: '[WARNING] CloudBridge Edge PoP Alert'
    body: |
      {{ range .Alerts }}
      Alert: {{ .Annotations.summary }}
      Description: {{ .Annotations.description }}
      Region: {{ .Labels.region }}
      Service: {{ .Labels.service }}
      {{ end }}
```

## Grafana Dashboards

### Edge PoP Overview Dashboard

```json
{
  "dashboard": {
    "title": "Edge PoP Overview",
    "panels": [
      {
        "title": "Inter-PoP RTT",
        "type": "graph",
        "targets": [
          {
            "expr": "relay_rtt_seconds{region=~\"mow|fra|ams\"}",
            "legendFormat": "{{region}} RTT"
          }
        ],
        "yAxes": [
          {
            "label": "RTT (seconds)",
            "max": 0.1
          }
        ]
      },
      {
        "title": "Handover Performance",
        "type": "graph",
        "targets": [
          {
            "expr": "relay_handover_duration_seconds",
            "legendFormat": "Handover Duration"
          }
        ],
        "yAxes": [
          {
            "label": "Duration (seconds)",
            "max": 0.5
          }
        ]
      },
      {
        "title": "P2P vs Relay Ratio",
        "type": "stat",
        "targets": [
          {
            "expr": "relay_p2p_percentage",
            "legendFormat": "P2P %"
          }
        ],
        "thresholds": [
          {
            "value": 60,
            "color": "red"
          },
          {
            "value": 80,
            "color": "yellow"
          },
          {
            "value": 90,
            "color": "green"
          }
        ]
      }
    ]
  }
}
```

### MASQUE Dashboard

```json
{
  "dashboard": {
    "title": "MASQUE Performance",
    "panels": [
      {
        "title": "Active Contexts",
        "type": "graph",
        "targets": [
          {
            "expr": "masque_active_contexts",
            "legendFormat": "{{region}} Active Contexts"
          }
        ]
      },
      {
        "title": "MASQUE Connections",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(masque_connections_total[5m])",
            "legendFormat": "{{region}} Connections/sec"
          }
        ]
      },
      {
        "title": "MASQUE Error Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(masque_errors_total[5m]) / rate(masque_connections_total[5m])",
            "legendFormat": "{{region}} Error Rate"
          }
        ]
      }
    ]
  }
}
```

## SLO Targets

### Availability SLO

| Service | Target | Measurement | Window |
|---------|--------|-------------|--------|
| Edge PoP Uptime | 99.9% | `up{job="edge-pops"}` | 30d |
| Inter-PoP Connectivity | 99.5% | `masque_neighbor_connectivity` | 30d |
| MASQUE Contexts | 99.0% | `masque_active_contexts / masque_max_contexts` | 30d |

### Performance SLO

| Metric | Target | Measurement | Window |
|--------|--------|-------------|--------|
| RTT p95 | < 50ms | `histogram_quantile(0.95, relay_rtt_seconds_bucket)` | 5m |
| Handover p95 | < 300ms | `histogram_quantile(0.95, relay_handover_duration_seconds_bucket)` | 5m |
| P2P Ratio | ≥ 60% | `relay_p2p_percentage` | 10m |
| Error Rate | < 1% | `rate(relay_errors_total[5m]) / rate(relay_requests_total[5m])` | 5m |
| Throughput | > 1Gbps | `relay_throughput_bytes` | 10m |

## Troubleshooting

### Common Monitoring Issues

#### 1. Metrics не собираются

**Симптомы:**
- Prometheus targets показывают "DOWN"
- Отсутствуют метрики в Grafana

**Решение:**
```bash
# Проверка Prometheus targets
kubectl port-forward -n cloudbridge-relay svc/prometheus 9090:9090
curl http://localhost:9090/api/v1/targets

# Проверка метрик endpoints
kubectl exec -n cloudbridge-relay deployment/relay-mow -- \
  curl -f http://localhost:9091/metrics

# Проверка Network Policies
kubectl get networkpolicies -n cloudbridge-relay
```

#### 2. Алерты не срабатывают

**Симптомы:**
- Алерты не приходят в Slack/Email
- Alertmanager показывает "inactive"

**Решение:**
```bash
# Проверка Alertmanager конфигурации
kubectl get configmap alertmanager-config -n cloudbridge-relay -o yaml

# Проверка статуса алертов
kubectl port-forward -n cloudbridge-relay svc/alertmanager 9093:9093
curl http://localhost:9093/api/v1/alerts

# Проверка логов Alertmanager
kubectl logs -n cloudbridge-relay -l app=alertmanager
```

#### 3. Grafana дашборды не загружаются

**Симптомы:**
- Дашборды показывают "No data"
- Ошибки в браузере

**Решение:**
```bash
# Проверка подключения к Prometheus
kubectl port-forward -n cloudbridge-relay svc/grafana 3000:3000

# Проверка Prometheus datasource
curl -u admin:password http://localhost:3000/api/datasources

# Проверка метрик
kubectl port-forward -n cloudbridge-relay svc/prometheus 9090:9090
curl http://localhost:9090/api/v1/query?query=up
```

### Debug Commands

```bash
# Проверка всех метрик
kubectl port-forward -n cloudbridge-relay svc/prometheus 9090:9090
curl http://localhost:9090/api/v1/label/__name__/values

# Проверка конкретной метрики
curl "http://localhost:9090/api/v1/query?query=relay_rtt_seconds"

# Проверка алертов
curl http://localhost:9090/api/v1/alerts

# Проверка правил
curl http://localhost:9090/api/v1/rules
```

## Performance Optimization

### Prometheus Tuning

```yaml
# Увеличение retention
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'cloudbridge-edge-pops'

# Оптимизация запросов
query:
  max_concurrency: 20
  timeout: 2m
  max_samples: 50000000
```

### Grafana Optimization

```yaml
# Кэширование дашбордов
[dashboards]
default_home_dashboard_path = /var/lib/grafana/dashboards/edge-pops.json

# Оптимизация запросов
[query_engine]
max_concurrent_queries = 20
query_timeout = 30s
```

## Future Enhancements

### Planned Features

1. **Advanced Analytics**
   - Machine learning для anomaly detection
   - Predictive scaling
   - Cost optimization insights

2. **Enhanced Dashboards**
   - Real-time topology maps
   - Interactive network graphs
   - Custom business metrics

3. **Integration**
   - PagerDuty integration
   - Jira ticket creation
   - Custom webhook endpoints


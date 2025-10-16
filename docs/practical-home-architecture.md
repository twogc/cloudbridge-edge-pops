# Практичная архитектура CloudBridge для домашних сетей

## 🏠 Домашняя архитектура (end-to-end)

```mermaid
flowchart LR
  U[Игровой ПК / ТВ-приставка / Смарт-ТВ] -->|LAN 1/2.5/10G| HGW[Домашний роутер<br/>SQM (CAKE/fq_codel)]
  HGW -->|QUIC :443/UDP| POP[Edge PoP (MOW/FRA/AMS)<br/>Anycast + MASQUE + BBRv2 + FEC]
  POP -->|Smart Routing / Inter-PoP| CORE[CloudBridge Core / Upstream CDN/Игра]
  
  subgraph Home
    U
    HGW
  end
  subgraph Edge/Backbone
    POP
    CORE
  end
```

## 🔧 SQM конфигурации для популярных роутеров

### **OpenWrt (CAKE)**
```bash
# /etc/config/qos
config qos
    option enabled '1'
    option download '850000'  # 85% от канала
    option upload '850000'    # 85% от канала
    option qdisc 'cake'
    option script 'piece_of_cake.qos'

# Gaming priority
config qos_rule
    option name 'Gaming'
    option proto 'udp'
    option dest_port '443,51820,3478'
    option dscp 'CS6'
    option priority '1'
```

### **MikroTik (HTB)**
```bash
# Queue Tree
/queue tree add name="Gaming" parent=global priority=1/1 packet-mark=gaming
/queue tree add name="Streaming" parent=global priority=2/2 packet-mark=streaming
/queue tree add name="Default" parent=global priority=3/3

# Packet Marking
/ip firewall mangle add chain=forward protocol=udp dst-port=443,51820,3478 action=mark-packet new-packet-mark=gaming
/ip firewall mangle add chain=forward protocol=tcp dst-port=80,443 action=mark-packet new-packet-mark=streaming
```

### **EdgeOS (fq_codel)**
```bash
# Traffic Control
tc qdisc add dev eth0 root handle 1: htb default 30
tc class add dev eth0 parent 1: classid 1:1 htb rate 850mbit ceil 1000mbit
tc class add dev eth0 parent 1:1 classid 1:10 htb rate 200mbit ceil 300mbit prio 1
tc class add dev eth0 parent 1:1 classid 1:20 htb rate 400mbit ceil 500mbit prio 2
tc class add dev eth0 parent 1:1 classid 1:30 htb rate 250mbit ceil 200mbit prio 3

# Gaming queue
tc qdisc add dev eth0 parent 1:10 fq_codel quantum 300 limit 1024
# Streaming queue  
tc qdisc add dev eth0 parent 1:20 fq_codel quantum 300 limit 1024
# Default queue
tc qdisc add dev eth0 parent 1:30 fq_codel quantum 300 limit 1024
```

## 📱 Мобильные сети - MP-QUIC + L4S

```mermaid
flowchart LR
  M[Мобильный клиент<br/>4G/5G] -->|MP-QUIC/QUIC<br/>L4S/ECN| EP[Edge PoP (опорная зона)]
  M -->|Failover| WiFi[Wi-Fi Calling/Домашний Wi-Fi]
  EP -->|MASQUE Smart Routing| Backbone[Backbone/Inter-PoP]
  EP --> CDN[CDN/Игровой сервер]
  
  subgraph RAN/Core
    gNB[Базовая станция / gNB]
    UPF[UPF/5GC]
  end
  M --> gNB --> UPF --> EP
```

## 🎮 Профили настроек

### **Gaming Profile**
```yaml
# k8s/gaming-profile.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: gaming-profile
  namespace: cloudbridge-relay
data:
  quic_config.yaml: |
    congestion_control: "bbr2"
    ack_frequency: "aggressive"
    pacing: true
    fec_enabled: false
    target_rtt: 20ms
    max_rtt: 50ms
    
  masque_config.yaml: |
    smart_routing: true
    fallback_threshold: 45ms
    handover_hysteresis: 10ms
    max_handovers_per_hour: 3
    
  dscp_marking:
    gaming: "CS6"
    voice: "EF"
    video: "AF41"
```

### **Streaming Profile**
```yaml
# k8s/streaming-profile.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: streaming-profile
  namespace: cloudbridge-relay
data:
  quic_config.yaml: |
    congestion_control: "bbr2"
    ack_frequency: "moderate"
    pacing: true
    fec_enabled: true
    fec_overhead: 8
    target_rtt: 30ms
    max_rtt: 100ms
    
  abr_config.yaml: |
    algorithm: "bola"
    prefetch_segments: 4
    gentle_downshift: true
    stall_threshold: 0.3%
    rebuffer_limit: 0.2/hour
```

## 📊 SLO метрики для домашних сетей

| Метрика | Домашние сети | Мобильные сети | Критичность |
|---------|---------------|----------------|-------------|
| `rtt_p95_home→pop` | < 20-25ms | < 35-45ms | Critical |
| `rtt_p95_pop→cdn` | < 25ms | < 30ms | Critical |
| `jitter_p95` | < 8ms | < 12ms | High |
| `loss_ratio` | < 0.5% | < 1.0% | High |
| `turn_fallback_ratio` | < 5% | < 10% | Medium |
| `stall_ratio` | < 0.3% | < 0.5% | High |
| `rebuffer_events` | < 0.2/hour | < 0.5/hour | High |
| `ping_spike_rate` | < 2/5min | < 3/5min | Medium |

## 🚨 Алерты для праймтайма

```yaml
# prometheus/prime-time-alerts.yaml
groups:
- name: prime_time_alerts
  rules:
  - alert: HighHomeRTT
    expr: histogram_quantile(0.95, relay_rtt_seconds{source="home"}) > 0.025
    for: 2m
    labels:
      severity: critical
      profile: "gaming"
    annotations:
      summary: "High RTT from home to PoP"
      description: "RTT p95 is {{ $value }}s, threshold is 25ms"
      
  - alert: MobileCongestion
    expr: relay_radio_congestion_score > 0.7
    for: 1m
    labels:
      severity: warning
      profile: "mobile"
    annotations:
      summary: "Mobile radio congestion detected"
      description: "Congestion score is {{ $value }}, consider handover"
      
  - alert: StreamingStall
    expr: relay_stall_ratio > 0.003
    for: 5m
    labels:
      severity: warning
      profile: "streaming"
    annotations:
      summary: "High streaming stall ratio"
      description: "Stall ratio is {{ $value }}%, threshold is 0.3%"
```

## 🔄 Автоматические переключения

### **Handover Policy**
```yaml
# k8s/handover-policy.yaml
apiVersion: cloudbridge.io/v1
kind: HandoverPolicy
metadata:
  name: prime-time-handover
spec:
  triggers:
    - metric: "rtt_p95"
      threshold: 45ms
      duration: 30s
    - metric: "loss_ratio" 
      threshold: 0.7%
      duration: 15s
    - metric: "jitter_p95"
      threshold: 12ms
      duration: 20s
      
  actions:
    - type: "pop_switch"
      target: "nearest_available"
      cooldown: 300s
    - type: "path_switch"
      target: "masque_tunnel"
      cooldown: 60s
      
  limits:
    max_handovers_per_hour: 3
    max_handovers_per_day: 10
```

## 📈 Мониторинг эффективности

### **Grafana Dashboard - Home Networks**
```json
{
  "dashboard": {
    "title": "CloudBridge Home Networks",
    "panels": [
      {
        "title": "RTT by Profile",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, relay_rtt_seconds) by (profile)",
            "legendFormat": "{{profile}} RTT p95"
          }
        ],
        "thresholds": [
          {"value": 0.025, "color": "red", "op": "gt"}
        ]
      },
      {
        "title": "SQM Effectiveness",
        "type": "stat",
        "targets": [
          {
            "expr": "relay_sqm_bufferbloat_reduction",
            "legendFormat": "Bufferbloat Reduction %"
          }
        ]
      }
    ]
  }
}
```

## 🛠️ Быстрый чек-лист внедрения

### **Домашний сегмент**
- [ ] Включить **SQM (CAKE)** на роутере, лимит 85-90% канала
- [ ] Игровые/стрим-клиенты на **5/6 ГГц**, отдельный SSID для IoT
- [ ] QUIC-клиенты → ближайший **Edge PoP (Anycast)**
- [ ] На PoP: **BBRv2 + ACK-Frequency + FEC + MASQUE**
- [ ] ABR-плеер с мягкой деградацией, prefetch 2-4 сегмента
- [ ] Мониторинг: `rtt_p95`, `jitter_p95`, `stall_ratio`

### **Сотовые сети**
- [ ] **MP-QUIC** / резервный путь (Wi-Fi-offload)
- [ ] Попытаться **L4S/ECN** (если у оператора доступно)
- [ ] MTU 1200-1350, pacing, FEC ~5-12%
- [ ] Edge PoP **рядом с UPF** (минимальный core-RTT)
- [ ] MASQUE для объезда перегрузок, алерты по `ping_spike_rate`

## 🎯 Готовые пресеты

### **Gaming Profile**
- QUIC: BBRv2, cwnd conservative старт, ACK-freq ↑
- SQM: строгий, DSCP приоритизация игр, target latency ≤ 15-20ms
- Мониторинг: `p99_rtt`, `spike_rate`, `jitter_p95`

### **Streaming Profile (VOD/Live)**
- QUIC: BBRv2, **FEC 8-10%**, ACK-freq умеренная, pacing включён
- ABR: низкая агрессивность дауншифта, prefetch 3-4 сегмента
- Мониторинг: `stall_ratio`, `rebuffer_events`, `abr_switches`

### **Household Prime-time**
- SQM: лимит временно 80-85% от канала (праймтайм-шедулер)
- Policy: игры/видеозвонки в приоритете, VOD в "background"
- Edge PoP: разрешить **меж-PoP перелив** при `loss>0.7%` или `rtt_p95>45ms`

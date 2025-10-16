# Edge PoP Troubleshooting Guide

## Overview

Этот документ содержит руководство по диагностике и устранению неполадок в системе Edge PoP узлов CloudBridge Relay.

## Quick Diagnostics

### Health Check Commands

```bash
# Общий статус системы
kubectl get all -n cloudbridge-relay

# Статус PoP узлов
kubectl get pods -n cloudbridge-relay -l app=cloudbridge-relay

# Статус сервисов
kubectl get services -n cloudbridge-relay

# Статус Network Policies
kubectl get networkpolicies -n cloudbridge-relay

# Статус ConfigMaps и Secrets
kubectl get configmaps,secrets -n cloudbridge-relay
```

### Quick Health Tests

```bash
# Тест связности
./scripts/test-inter-pop-connectivity.sh

# Тест MASQUE
./scripts/test-masque.sh

# Тест handover
./scripts/test-handover.sh
```

## Common Issues

### 1. PoP Pods не запускаются

#### Симптомы
- Pods в состоянии `Pending`, `CrashLoopBackOff`, или `Error`
- Ошибки в логах: "ImagePullBackOff", "CrashLoopBackOff"

#### Диагностика
```bash
# Проверка статуса подов
kubectl get pods -n cloudbridge-relay -o wide

# Проверка событий
kubectl get events -n cloudbridge-relay --sort-by='.lastTimestamp'

# Проверка логов
kubectl logs -n cloudbridge-relay -l app=cloudbridge-relay --tail=100

# Проверка описания пода
kubectl describe pod <pod-name> -n cloudbridge-relay
```

#### Решения

**ImagePullBackOff:**
```bash
# Проверка доступности образа
kubectl get pod <pod-name> -n cloudbridge-relay -o yaml | grep image

# Проверка registry
docker pull cloudbridge-relay:mvp-20251011-214615

# Обновление imagePullPolicy
kubectl patch deployment cloudbridge-relay -n cloudbridge-relay -p '{"spec":{"template":{"spec":{"containers":[{"name":"cloudbridge-relay","imagePullPolicy":"Always"}]}}}}'
```

**CrashLoopBackOff:**
```bash
# Проверка логов
kubectl logs -n cloudbridge-relay <pod-name> --previous

# Проверка конфигурации
kubectl get configmap cloudbridge-config-json -n cloudbridge-relay -o yaml

# Проверка ресурсов
kubectl top pods -n cloudbridge-relay
```

### 2. Inter-PoP связность нарушена

#### Симптомы
- `masque_neighbor_connectivity` = 0
- Ошибки в логах: "Connection refused", "Timeout"
- Метрики RTT показывают высокие значения

#### Диагностика
```bash
# Проверка MASQUE конфигурации
kubectl get configmap masque-config -n cloudbridge-relay -o yaml

# Проверка mTLS сертификатов
kubectl get secret cb-interpop-cert -n cloudbridge-relay

# Проверка Network Policies
kubectl get networkpolicies -n cloudbridge-relay

# Проверка DNS разрешения
kubectl exec -n cloudbridge-relay deployment/relay-mow -- nslookup fra.pop.cb
kubectl exec -n cloudbridge-relay deployment/relay-mow -- nslookup ams.pop.cb

# Проверка портов
kubectl exec -n cloudbridge-relay deployment/relay-mow -- netstat -tulpn | grep 9090
```

#### Решения

**DNS Issues:**
```bash
# Проверка CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Проверка DNS конфигурации
kubectl get configmap coredns -n kube-system -o yaml

# Добавление DNS записей
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: fra.pop.cb
  namespace: cloudbridge-relay
spec:
  type: ExternalName
  externalName: fra.pop.cb
EOF
```

**Network Policy Issues:**
```bash
# Проверка Network Policies
kubectl get networkpolicies -n cloudbridge-relay -o yaml

# Временное отключение Network Policies
kubectl delete networkpolicy relay-network-policy -n cloudbridge-relay

# Проверка связности
kubectl exec -n cloudbridge-relay deployment/relay-mow -- \
  curl -X POST http://ai-service:8083/api/routing/test-connectivity \
  -H "Content-Type: application/json" \
  -d '{"source": "mow", "targets": ["fra"]}'
```

### 3. mTLS ошибки

#### Симптомы
- Ошибки в логах: "TLS handshake failed", "Certificate verification failed"
- `masque_errors_total` увеличивается
- Соединения не устанавливаются

#### Диагностика
```bash
# Проверка сертификатов
kubectl get secret cb-interpop-cert -n cloudbridge-relay -o yaml

# Проверка CA bundle
kubectl get secret cb-ca-bundle -n cloudbridge-relay -o yaml

# Проверка cert-manager
kubectl get certificates -n cloudbridge-relay
kubectl get certificaterequests -n cloudbridge-relay

# Проверка логов cert-manager
kubectl logs -n cert-manager -l app=cert-manager
```

#### Решения

**Certificate Issues:**
```bash
# Обновление сертификатов
kubectl delete secret cb-interpop-cert -n cloudbridge-relay
kubectl apply -f masque/mtls-secrets.yaml

# Проверка cert-manager
kubectl get clusterissuer letsencrypt-prod

# Ручное обновление сертификата
kubectl create secret tls cb-interpop-cert \
  --cert=interpop.crt \
  --key=interpop.key \
  -n cloudbridge-relay
```

**CA Bundle Issues:**
```bash
# Обновление CA bundle
kubectl delete secret cb-ca-bundle -n cloudbridge-relay
kubectl create secret generic cb-ca-bundle \
  --from-file=ca.crt=ca.crt \
  --from-file=crl.pem=crl.pem \
  -n cloudbridge-relay
```

### 4. Высокий RTT между PoP

#### Симптомы
- `relay_rtt_seconds` > 50ms
- Алерты "HighRTT" срабатывают
- Пользователи жалуются на медленную работу

#### Диагностика
```bash
# Проверка RTT метрик
kubectl port-forward -n cloudbridge-relay svc/relay-mow 9091:9091
curl http://localhost:9091/metrics | grep relay_rtt_seconds

# Проверка сетевой связности
kubectl exec -n cloudbridge-relay deployment/relay-mow -- \
  ping -c 5 fra.pop.cb

# Проверка трассировки
kubectl exec -n cloudbridge-relay deployment/relay-mow -- \
  traceroute fra.pop.cb

# Проверка загрузки сети
kubectl exec -n cloudbridge-relay deployment/relay-mow -- \
  netstat -i
```

#### Решения

**Network Optimization:**
```bash
# Проверка Network Policies
kubectl get networkpolicies -n cloudbridge-relay -o yaml

# Оптимизация QUIC параметров
kubectl patch configmap masque-config -n cloudbridge-relay --type merge -p '{
  "data": {
    "masque.yaml": "quic:\n  bbr2: true\n  ack_frequency: true\n  keepalive: 5s"
  }
}'

# Перезапуск deployment
kubectl rollout restart deployment/relay-mow -n cloudbridge-relay
```

### 5. Handover превышает 300ms

#### Симптомы
- `relay_handover_duration_seconds` > 0.3
- Алерты "HandoverTimeout" срабатывают
- Пользователи испытывают задержки при переключении

#### Диагностика
```bash
# Проверка handover метрик
kubectl port-forward -n cloudbridge-relay svc/relay-mow 9091:9091
curl http://localhost:9091/metrics | grep relay_handover_duration_seconds

# Проверка AI service
kubectl exec -n cloudbridge-relay deployment/relay-mow -- \
  curl -f http://ai-service:8083/health

# Проверка конфигурации маршрутизации
kubectl get configmap masque-config -n cloudbridge-relay -o yaml | grep -A 10 routing
```

#### Решения

**AI Service Issues:**
```bash
# Проверка AI service
kubectl get pods -n cloudbridge-control -l app=ai-service

# Проверка логов AI service
kubectl logs -n cloudbridge-control -l app=ai-service --tail=100

# Fallback на latency-based маршрутизацию
kubectl patch configmap masque-config -n cloudbridge-relay --type merge -p '{
  "data": {
    "masque.yaml": "routing:\n  algorithm: \"latency_based\"\n  fallback_algorithm: \"round_robin\""
  }
}'
```

### 6. Низкий процент P2P соединений

#### Симптомы
- `relay_p2p_percentage` < 60%
- Алерты "LowP2PRatio" срабатывают
- Больше трафика идет через relay

#### Диагностика
```bash
# Проверка P2P метрик
kubectl port-forward -n cloudbridge-relay svc/relay-mow 9091:9091
curl http://localhost:9091/metrics | grep relay_p2p_percentage

# Проверка STUN сервера
kubectl exec -n cloudbridge-relay deployment/relay-mow -- \
  netstat -tulpn | grep 19302

# Проверка NAT traversal
kubectl exec -n cloudbridge-relay deployment/relay-mow -- \
  curl -X POST http://localhost:5550/api/nat/check
```

#### Решения

**STUN Server Issues:**
```bash
# Проверка STUN сервера
kubectl get service -n cloudbridge-relay | grep stun

# Проверка портов
kubectl get service cloudbridge-relay-external -n cloudbridge-relay -o yaml | grep -A 5 stun-server

# Перезапуск STUN сервера
kubectl rollout restart deployment/relay-mow -n cloudbridge-relay
```

## Advanced Troubleshooting

### Network Debugging

```bash
# Проверка сетевых интерфейсов
kubectl exec -n cloudbridge-relay deployment/relay-mow -- ip addr show

# Проверка маршрутов
kubectl exec -n cloudbridge-relay deployment/relay-mow -- ip route show

# Проверка iptables правил
kubectl exec -n cloudbridge-relay deployment/relay-mow -- iptables -L

# Проверка DNS
kubectl exec -n cloudbridge-relay deployment/relay-mow -- cat /etc/resolv.conf
```

### Performance Debugging

```bash
# Проверка CPU и памяти
kubectl top pods -n cloudbridge-relay

# Проверка дискового пространства
kubectl exec -n cloudbridge-relay deployment/relay-mow -- df -h

# Проверка процессов
kubectl exec -n cloudbridge-relay deployment/relay-mow -- ps aux

# Проверка файловых дескрипторов
kubectl exec -n cloudbridge-relay deployment/relay-mow -- lsof | wc -l
```

### Log Analysis

```bash
# Анализ логов по ошибкам
kubectl logs -n cloudbridge-relay -l app=cloudbridge-relay | grep -i error

# Анализ логов по предупреждениям
kubectl logs -n cloudbridge-relay -l app=cloudbridge-relay | grep -i warning

# Анализ логов по времени
kubectl logs -n cloudbridge-relay -l app=cloudbridge-relay --since=1h

# Анализ логов по конкретному региону
kubectl logs -n cloudbridge-relay -l app=cloudbridge-relay,region=mow
```

## Emergency Procedures

### Complete System Restart

```bash
# Остановка всех PoP
kubectl scale deployment relay-mow -n cloudbridge-relay --replicas=0
kubectl scale deployment relay-fra -n cloudbridge-relay --replicas=0
kubectl scale deployment relay-ams -n cloudbridge-relay --replicas=0

# Очистка ресурсов
kubectl delete networkpolicies --all -n cloudbridge-relay
kubectl delete configmaps --all -n cloudbridge-relay
kubectl delete secrets --all -n cloudbridge-relay

# Перезапуск системы
./scripts/deploy-edge-pops.sh
```

### Rollback to Previous Version

```bash
# Проверка истории deployment
kubectl rollout history deployment/relay-mow -n cloudbridge-relay

# Откат к предыдущей версии
kubectl rollout undo deployment/relay-mow -n cloudbridge-relay
kubectl rollout undo deployment/relay-fra -n cloudbridge-relay
kubectl rollout undo deployment/relay-ams -n cloudbridge-relay

# Проверка статуса
kubectl rollout status deployment/relay-mow -n cloudbridge-relay
```

### Data Recovery

```bash
# Резервное копирование конфигурации
kubectl get configmap masque-config -n cloudbridge-relay -o yaml > masque-config-backup.yaml
kubectl get secret cb-interpop-cert -n cloudbridge-relay -o yaml > mtls-secret-backup.yaml

# Восстановление конфигурации
kubectl apply -f masque-config-backup.yaml
kubectl apply -f mtls-secret-backup.yaml
```

## Monitoring and Alerting

### Health Check Endpoints

```bash
# Проверка health endpoint
kubectl exec -n cloudbridge-relay deployment/relay-mow -- \
  curl -f http://localhost:9091/health

# Проверка metrics endpoint
kubectl exec -n cloudbridge-relay deployment/relay-mow -- \
  curl -f http://localhost:9091/metrics

# Проверка MASQUE API
kubectl exec -n cloudbridge-relay deployment/relay-mow -- \
  curl -f http://localhost:9090/api/masque/contexts
```

### Alert Testing

```bash
# Тест критических алертов
kubectl exec -n cloudbridge-relay deployment/relay-mow -- \
  curl -X POST http://localhost:9091/api/test/alert \
  -H "Content-Type: application/json" \
  -d '{"alert": "PoPDown", "severity": "critical"}'

# Тест warning алертов
kubectl exec -n cloudbridge-relay deployment/relay-mow -- \
  curl -X POST http://localhost:9091/api/test/alert \
  -H "Content-Type: application/json" \
  -d '{"alert": "HighRTT", "severity": "warning"}'
```

## Best Practices

### Preventive Maintenance

1. **Регулярные проверки:**
   - Еженедельная проверка логов
   - Ежемесячная проверка сертификатов
   - Ежеквартальная проверка производительности

2. **Мониторинг:**
   - Настройка алертов для всех критических метрик
   - Регулярная проверка SLO compliance
   - Анализ трендов производительности

3. **Обновления:**
   - Регулярные обновления образов
   - Тестирование в staging среде
   - Поэтапное развертывание обновлений

### Documentation

1. **Ведение логов:**
   - Документирование всех инцидентов
   - Создание runbooks для типовых проблем
   - Обновление troubleshooting guide

2. **Обучение команды:**
   - Регулярные тренинги по диагностике
   - Практические сессии по troubleshooting
   - Обмен опытом между командами


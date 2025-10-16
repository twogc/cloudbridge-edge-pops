#!/bin/bash
# scripts/test-pop-ams.sh

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции для логирования
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Функция проверки доступности PoP
check_pop_availability() {
    local region="ams"
    local namespace="cloudbridge-relay"
    
    log "Проверка доступности Amsterdam PoP..."
    
    # Проверка наличия подов
    local pod_count=$(kubectl get pods -n $namespace -l app=cloudbridge-relay,region=$region --no-headers | wc -l)
    if [ $pod_count -eq 0 ]; then
        error "Amsterdam PoP не найден"
        return 1
    fi
    
    # Проверка готовности подов
    local ready_pods=$(kubectl get pods -n $namespace -l app=cloudbridge-relay,region=$region --field-selector=status.phase=Running --no-headers | wc -l)
    if [ $ready_pods -eq 0 ]; then
        error "Amsterdam PoP не готов"
        return 1
    fi
    
    success "Amsterdam PoP доступен ($ready_pods/$pod_count pods готовы)"
    return 0
}

# Функция проверки health endpoint
check_health_endpoint() {
    local region="ams"
    local namespace="cloudbridge-relay"
    
    log "Проверка health endpoint для Amsterdam PoP..."
    
    local pod_name=$(kubectl get pods -n $namespace -l app=cloudbridge-relay,region=$region -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$pod_name" ]; then
        error "Pod для Amsterdam PoP не найден"
        return 1
    fi
    
    # Проверка health endpoint
    if ! kubectl exec -n $namespace $pod_name -- curl -f http://localhost:9091/health >/dev/null 2>&1; then
        error "Health endpoint недоступен для $pod_name"
        return 1
    fi
    
    success "Health endpoint доступен для $pod_name"
    return 0
}

# Функция проверки метрик
check_metrics() {
    local region="ams"
    local namespace="cloudbridge-relay"
    
    log "Проверка метрик для Amsterdam PoP..."
    
    local pod_name=$(kubectl get pods -n $namespace -l app=cloudbridge-relay,region=$region -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$pod_name" ]; then
        error "Pod для Amsterdam PoP не найден"
        return 1
    fi
    
    # Получение метрик
    local metrics_response=$(kubectl exec -n $namespace $pod_name -- \
      curl -s http://localhost:9091/metrics 2>/dev/null || echo "Metrics недоступны")
    
    if [ "$metrics_response" = "Metrics недоступны" ]; then
        error "Метрики недоступны для $pod_name"
        return 1
    fi
    
    # Проверка ключевых метрик
    local rtt_metric=$(echo "$metrics_response" | grep "relay_rtt_seconds" | head -1)
    local handover_metric=$(echo "$metrics_response" | grep "relay_handover_duration_seconds" | head -1)
    local p2p_metric=$(echo "$metrics_response" | grep "relay_p2p_percentage" | head -1)
    local error_metric=$(echo "$metrics_response" | grep "relay_error_rate" | head -1)
    local throughput_metric=$(echo "$metrics_response" | grep "relay_throughput_bytes" | head -1)
    
    if [ -n "$rtt_metric" ]; then
        success "RTT метрика доступна: $rtt_metric"
    else
        warning "RTT метрика не найдена"
    fi
    
    if [ -n "$handover_metric" ]; then
        success "Handover метрика доступна: $handover_metric"
    else
        warning "Handover метрика не найдена"
    fi
    
    if [ -n "$p2p_metric" ]; then
        success "P2P метрика доступна: $p2p_metric"
    else
        warning "P2P метрика не найдена"
    fi
    
    if [ -n "$error_metric" ]; then
        success "Error rate метрика доступна: $error_metric"
    else
        warning "Error rate метрика не найдена"
    fi
    
    if [ -n "$throughput_metric" ]; then
        success "Throughput метрика доступна: $throughput_metric"
    else
        warning "Throughput метрика не найдена"
    fi
    
    return 0
}

# Функция проверки портов
check_ports() {
    local region="ams"
    local namespace="cloudbridge-relay"
    
    log "Проверка портов для Amsterdam PoP..."
    
    local pod_name=$(kubectl get pods -n $namespace -l app=cloudbridge-relay,region=$region -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$pod_name" ]; then
        error "Pod для Amsterdam PoP не найден"
        return 1
    fi
    
    # Проверка основных портов
    local ports=("5550:main-server" "5551:metrics" "5552:p2p-api" "5553:http-api" "5554:https-api" "5555:quic-transport" "9090:quic-legacy" "9092:enhanced-quic" "19302:stun-server")
    
    for port_info in "${ports[@]}"; do
        local port=$(echo $port_info | cut -d: -f1)
        local name=$(echo $port_info | cut -d: -f2)
        
        if kubectl exec -n $namespace $pod_name -- netstat -tulpn | grep -q ":$port "; then
            success "Порт $port ($name) открыт"
        else
            warning "Порт $port ($name) не найден"
        fi
    done
    
    return 0
}

# Функция проверки сервисов
check_services() {
    local namespace="cloudbridge-relay"
    
    log "Проверка сервисов для Amsterdam PoP..."
    
    # Проверка основных сервисов
    local services=("cloudbridge-relay-external" "cloudbridge-relay-lb-tcp" "cloudbridge-relay-lb-udp")
    
    for service in "${services[@]}"; do
        if kubectl get service $service -n $namespace >/dev/null 2>&1; then
            success "Сервис $service найден"
            
            # Проверка endpoints
            local endpoint_count=$(kubectl get endpoints $service -n $namespace -o jsonpath='{.subsets[0].addresses[*].ip}' | wc -w)
            if [ $endpoint_count -gt 0 ]; then
                success "Endpoints для $service: $endpoint_count"
            else
                warning "Endpoints для $service не найдены"
            fi
        else
            warning "Сервис $service не найден"
        fi
    done
    
    return 0
}

# Функция проверки Network Policies
check_network_policies() {
    local namespace="cloudbridge-relay"
    
    log "Проверка Network Policies для Amsterdam PoP..."
    
    local policy_count=$(kubectl get networkpolicies -n $namespace --no-headers | wc -l)
    if [ $policy_count -eq 0 ]; then
        warning "Network Policies не найдены"
        return 1
    fi
    
    success "Найдено $policy_count Network Policies"
    
    # Проверка конкретных политик
    if kubectl get networkpolicy relay-network-policy -n $namespace >/dev/null 2>&1; then
        success "relay-network-policy найдена"
    else
        warning "relay-network-policy не найдена"
    fi
    
    if kubectl get networkpolicy tenant-isolation -n $namespace >/dev/null 2>&1; then
        success "tenant-isolation policy найдена"
    else
        warning "tenant-isolation policy не найдена"
    fi
    
    return 0
}

# Функция проверки конфигурации
check_configuration() {
    local region="ams"
    local namespace="cloudbridge-relay"
    
    log "Проверка конфигурации для Amsterdam PoP..."
    
    # Проверка ConfigMap
    if kubectl get configmap cloudbridge-config-json -n $namespace >/dev/null 2>&1; then
        success "ConfigMap cloudbridge-config-json найден"
    else
        error "ConfigMap cloudbridge-config-json не найден"
        return 1
    fi
    
    # Проверка Secrets
    if kubectl get secret cloudbridge-tls -n $namespace >/dev/null 2>&1; then
        success "Secret cloudbridge-tls найден"
    else
        warning "Secret cloudbridge-tls не найден"
    fi
    
    # Проверка MASQUE конфигурации
    if kubectl get configmap masque-config -n $namespace >/dev/null 2>&1; then
        success "MASQUE ConfigMap найден"
    else
        warning "MASQUE ConfigMap не найден"
    fi
    
    return 0
}

# Функция проверки производительности
check_performance() {
    local region="ams"
    local namespace="cloudbridge-relay"
    
    log "Проверка производительности Amsterdam PoP..."
    
    local pod_name=$(kubectl get pods -n $namespace -l app=cloudbridge-relay,region=$region -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$pod_name" ]; then
        error "Pod для Amsterdam PoP не найден"
        return 1
    fi
    
    # Проверка использования ресурсов
    local cpu_usage=$(kubectl top pod $pod_name -n $namespace --no-headers | awk '{print $2}' | sed 's/m//')
    local memory_usage=$(kubectl top pod $pod_name -n $namespace --no-headers | awk '{print $3}' | sed 's/Mi//')
    
    if [ -n "$cpu_usage" ] && [ "$cpu_usage" -lt 500 ]; then
        success "CPU использование в норме: ${cpu_usage}m"
    else
        warning "CPU использование высокое: ${cpu_usage}m"
    fi
    
    if [ -n "$memory_usage" ] && [ "$memory_usage" -lt 512 ]; then
        success "Memory использование в норме: ${memory_usage}Mi"
    else
        warning "Memory использование высокое: ${memory_usage}Mi"
    fi
    
    return 0
}

# Основная функция
main() {
    echo "🏢 Тестирование Amsterdam PoP (EU-AMS)"
    echo "======================================="
    
    local exit_code=0
    
    # Проверка доступности PoP
    check_pop_availability || exit_code=1
    
    # Проверка health endpoint
    check_health_endpoint || exit_code=1
    
    # Проверка метрик
    check_metrics || exit_code=1
    
    # Проверка портов
    check_ports || exit_code=1
    
    # Проверка сервисов
    check_services || exit_code=1
    
    # Проверка Network Policies
    check_network_policies || exit_code=1
    
    # Проверка конфигурации
    check_configuration || exit_code=1
    
    # Проверка производительности
    check_performance || exit_code=1
    
    # Итоговый результат
    if [ $exit_code -eq 0 ]; then
        success "✅ Все тесты Amsterdam PoP прошли успешно!"
    else
        error "❌ Некоторые тесты Amsterdam PoP не прошли"
    fi
    
    echo ""
    echo "📊 Статус Amsterdam PoP:"
    kubectl get pods -n cloudbridge-relay -l app=cloudbridge-relay,region=ams
    
    echo ""
    echo "🔍 Полезные команды:"
    echo "  - Логи: kubectl logs -n cloudbridge-relay -l app=cloudbridge-relay,region=ams"
    echo "  - Метрики: kubectl port-forward -n cloudbridge-relay svc/relay-ams 9091:9091"
    echo "  - Сервисы: kubectl get services -n cloudbridge-relay | grep ams"
    echo "  - Network Policies: kubectl get networkpolicies -n cloudbridge-relay"
    
    exit $exit_code
}

# Запуск основной функции
main "$@"

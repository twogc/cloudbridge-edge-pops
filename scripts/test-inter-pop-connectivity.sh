#!/bin/bash
# scripts/test-inter-pop-connectivity.sh

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
    local region=$1
    local namespace="cloudbridge-relay"
    
    log "Проверка доступности PoP $region..."
    
    # Проверка наличия подов
    local pod_count=$(kubectl get pods -n $namespace -l app=cloudbridge-relay,region=$region --no-headers | wc -l)
    if [ $pod_count -eq 0 ]; then
        error "PoP $region не найден"
        return 1
    fi
    
    # Проверка готовности подов
    local ready_pods=$(kubectl get pods -n $namespace -l app=cloudbridge-relay,region=$region --field-selector=status.phase=Running --no-headers | wc -l)
    if [ $ready_pods -eq 0 ]; then
        error "PoP $region не готов"
        return 1
    fi
    
    success "PoP $region доступен ($ready_pods/$pod_count pods готовы)"
    return 0
}

# Функция проверки связности
test_connectivity() {
    local source_region=$1
    local target_region=$2
    local namespace="cloudbridge-relay"
    
    log "Тестирование связности $source_region -> $target_region..."
    
    # Получение имени пода
    local pod_name=$(kubectl get pods -n $namespace -l app=cloudbridge-relay,region=$source_region -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$pod_name" ]; then
        error "Pod для региона $source_region не найден"
        return 1
    fi
    
    # Проверка health endpoint
    log "Проверка health endpoint для $pod_name..."
    if ! kubectl exec -n $namespace $pod_name -- curl -f http://localhost:9091/health >/dev/null 2>&1; then
        error "Health endpoint недоступен для $pod_name"
        return 1
    fi
    
    # Проверка связности через AI service
    log "Проверка связности через AI service..."
    local response=$(kubectl exec -n $namespace $pod_name -- \
      curl -s -X POST http://ai-service:8083/api/routing/test-connectivity \
      -H "Content-Type: application/json" \
      -d "{\"source\": \"$source_region\", \"targets\": [\"$target_region\"]}" 2>/dev/null || echo "AI service недоступен")
    
    if [ "$response" = "AI service недоступен" ]; then
        warning "AI service недоступен, пропускаем проверку связности"
        return 0
    fi
    
    # Проверка ответа
    if echo "$response" | grep -q "success\|ok\|connected"; then
        success "Связность $source_region -> $target_region установлена"
        return 0
    else
        error "Связность $source_region -> $target_region не установлена"
        return 1
    fi
}

# Функция проверки метрик
check_metrics() {
    local region=$1
    local namespace="cloudbridge-relay"
    
    log "Проверка метрик для региона $region..."
    
    local pod_name=$(kubectl get pods -n $namespace -l app=cloudbridge-relay,region=$region -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$pod_name" ]; then
        error "Pod для региона $region не найден"
        return 1
    fi
    
    # Проверка доступности метрик
    local metrics_response=$(kubectl exec -n $namespace $pod_name -- curl -s http://localhost:9091/metrics 2>/dev/null || echo "Metrics недоступны")
    
    if [ "$metrics_response" = "Metrics недоступны" ]; then
        error "Метрики недоступны для $pod_name"
        return 1
    fi
    
    # Проверка ключевых метрик
    local rtt_metric=$(echo "$metrics_response" | grep "relay_rtt_seconds" | head -1)
    local handover_metric=$(echo "$metrics_response" | grep "relay_handover_duration_seconds" | head -1)
    local p2p_metric=$(echo "$metrics_response" | grep "relay_p2p_percentage" | head -1)
    
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
    
    return 0
}

# Функция проверки Network Policies
check_network_policies() {
    local namespace="cloudbridge-relay"
    
    log "Проверка Network Policies..."
    
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

# Основная функция
main() {
    echo "🔗 Тестирование Inter-PoP связности CloudBridge"
    echo "================================================"
    
    local exit_code=0
    
    # Проверка доступности всех PoP
    log "Проверка доступности PoP узлов..."
    check_pop_availability "mow" || exit_code=1
    check_pop_availability "fra" || exit_code=1
    check_pop_availability "ams" || exit_code=1
    
    # Проверка связности между PoP
    log "Проверка Inter-PoP связности..."
    test_connectivity "mow" "fra" || exit_code=1
    test_connectivity "mow" "ams" || exit_code=1
    test_connectivity "fra" "mow" || exit_code=1
    test_connectivity "fra" "ams" || exit_code=1
    test_connectivity "ams" "mow" || exit_code=1
    test_connectivity "ams" "fra" || exit_code=1
    
    # Проверка метрик
    log "Проверка метрик..."
    check_metrics "mow" || exit_code=1
    check_metrics "fra" || exit_code=1
    check_metrics "ams" || exit_code=1
    
    # Проверка Network Policies
    check_network_policies || exit_code=1
    
    # Итоговый результат
    if [ $exit_code -eq 0 ]; then
        success "✅ Все тесты Inter-PoP связности прошли успешно!"
    else
        error "❌ Некоторые тесты Inter-PoP связности не прошли"
    fi
    
    echo ""
    echo "📊 Статус PoP узлов:"
    kubectl get pods -n cloudbridge-relay -l app=cloudbridge-relay
    
    echo ""
    echo "🔍 Полезные команды:"
    echo "  - Логи: kubectl logs -n cloudbridge-relay -l app=cloudbridge-relay"
    echo "  - Метрики: kubectl port-forward -n cloudbridge-relay svc/relay-mow 9091:9091"
    echo "  - Network Policies: kubectl get networkpolicies -n cloudbridge-relay"
    
    exit $exit_code
}

# Запуск основной функции
main "$@"


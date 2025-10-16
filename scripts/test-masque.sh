#!/bin/bash
# scripts/test-masque.sh

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

# Функция проверки MASQUE конфигурации
check_masque_config() {
    local namespace="cloudbridge-relay"
    
    log "Проверка MASQUE конфигурации..."
    
    # Проверка ConfigMap
    if ! kubectl get configmap masque-config -n $namespace >/dev/null 2>&1; then
        error "MASQUE ConfigMap не найден"
        return 1
    fi
    
    success "MASQUE ConfigMap найден"
    
    # Проверка содержимого конфигурации
    local config_data=$(kubectl get configmap masque-config -n $namespace -o jsonpath='{.data.masque\.yaml}')
    
    if echo "$config_data" | grep -q "quic:"; then
        success "QUIC конфигурация найдена"
    else
        error "QUIC конфигурация не найдена"
        return 1
    fi
    
    if echo "$config_data" | grep -q "mtls:"; then
        success "mTLS конфигурация найдена"
    else
        error "mTLS конфигурация не найдена"
        return 1
    fi
    
    if echo "$config_data" | grep -q "neighbors:"; then
        success "Neighbors конфигурация найдена"
    else
        error "Neighbors конфигурация не найдена"
        return 1
    fi
    
    return 0
}

# Функция проверки mTLS сертификатов
check_mtls_certs() {
    local namespace="cloudbridge-relay"
    
    log "Проверка mTLS сертификатов..."
    
    # Проверка сертификатов
    if ! kubectl get secret cb-interpop-cert -n $namespace >/dev/null 2>&1; then
        error "mTLS сертификат не найден"
        return 1
    fi
    
    success "mTLS сертификат найден"
    
    # Проверка CA bundle
    if ! kubectl get secret cb-ca-bundle -n $namespace >/dev/null 2>&1; then
        warning "CA bundle не найден"
        return 1
    fi
    
    success "CA bundle найден"
    
    return 0
}

# Функция проверки MASQUE контекстов
check_masque_contexts() {
    local region=$1
    local namespace="cloudbridge-relay"
    
    log "Проверка MASQUE контекстов для региона $region..."
    
    local pod_name=$(kubectl get pods -n $namespace -l app=cloudbridge-relay,region=$region -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$pod_name" ]; then
        error "Pod для региона $region не найден"
        return 1
    fi
    
    # Проверка MASQUE API
    local contexts_response=$(kubectl exec -n $namespace $pod_name -- \
      curl -s http://localhost:9090/api/masque/contexts 2>/dev/null || echo "MASQUE API недоступен")
    
    if [ "$contexts_response" = "MASQUE API недоступен" ]; then
        error "MASQUE API недоступен для $pod_name"
        return 1
    fi
    
    success "MASQUE API доступен для $pod_name"
    
    # Проверка статистики MASQUE
    local stats_response=$(kubectl exec -n $namespace $pod_name -- \
      curl -s http://localhost:9090/api/masque/stats 2>/dev/null || echo "MASQUE stats недоступны")
    
    if [ "$stats_response" = "MASQUE stats недоступны" ]; then
        warning "MASQUE статистика недоступна"
    else
        success "MASQUE статистика доступна"
    fi
    
    return 0
}

# Функция проверки MASQUE метрик
check_masque_metrics() {
    local region=$1
    local namespace="cloudbridge-relay"
    
    log "Проверка MASQUE метрик для региона $region..."
    
    local pod_name=$(kubectl get pods -n $namespace -l app=cloudbridge-relay,region=$region -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$pod_name" ]; then
        error "Pod для региона $region не найден"
        return 1
    fi
    
    # Получение метрик
    local metrics_response=$(kubectl exec -n $namespace $pod_name -- \
      curl -s http://localhost:9091/metrics 2>/dev/null || echo "Metrics недоступны")
    
    if [ "$metrics_response" = "Metrics недоступны" ]; then
        error "Метрики недоступны для $pod_name"
        return 1
    fi
    
    # Проверка MASQUE метрик
    local masque_contexts=$(echo "$metrics_response" | grep "masque_active_contexts" | head -1)
    local masque_connections=$(echo "$metrics_response" | grep "masque_connections_total" | head -1)
    local masque_errors=$(echo "$metrics_response" | grep "masque_errors_total" | head -1)
    
    if [ -n "$masque_contexts" ]; then
        success "MASQUE контексты метрика: $masque_contexts"
    else
        warning "MASQUE контексты метрика не найдена"
    fi
    
    if [ -n "$masque_connections" ]; then
        success "MASQUE соединения метрика: $masque_connections"
    else
        warning "MASQUE соединения метрика не найдена"
    fi
    
    if [ -n "$masque_errors" ]; then
        success "MASQUE ошибки метрика: $masque_errors"
    else
        warning "MASQUE ошибки метрика не найдена"
    fi
    
    return 0
}

# Функция проверки соседей
check_masque_neighbors() {
    local region=$1
    local namespace="cloudbridge-relay"
    
    log "Проверка MASQUE соседей для региона $region..."
    
    local pod_name=$(kubectl get pods -n $namespace -l app=cloudbridge-relay,region=$region -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$pod_name" ]; then
        error "Pod для региона $region не найден"
        return 1
    fi
    
    # Проверка соседей
    local neighbors_response=$(kubectl exec -n $namespace $pod_name -- \
      curl -s http://localhost:9090/api/masque/neighbors 2>/dev/null || echo "Neighbors API недоступен")
    
    if [ "$neighbors_response" = "Neighbors API недоступен" ]; then
        error "Neighbors API недоступен для $pod_name"
        return 1
    fi
    
    success "Neighbors API доступен для $pod_name"
    
    # Проверка связности с соседями
    local connectivity_response=$(kubectl exec -n $namespace $pod_name -- \
      curl -s http://localhost:9090/api/masque/connectivity 2>/dev/null || echo "Connectivity API недоступен")
    
    if [ "$connectivity_response" = "Connectivity API недоступен" ]; then
        warning "Connectivity API недоступен"
    else
        success "Connectivity API доступен"
    fi
    
    return 0
}

# Функция проверки безопасности MASQUE
check_masque_security() {
    local namespace="cloudbridge-relay"
    
    log "Проверка безопасности MASQUE..."
    
    # Проверка Network Policies
    if kubectl get networkpolicy relay-network-policy -n $namespace >/dev/null 2>&1; then
        success "Network Policy для MASQUE найдена"
    else
        error "Network Policy для MASQUE не найдена"
        return 1
    fi
    
    # Проверка Calico GlobalNetworkPolicy
    if kubectl get globalnetworkpolicy inter-pop-allow >/dev/null 2>&1; then
        success "Calico GlobalNetworkPolicy найдена"
    else
        warning "Calico GlobalNetworkPolicy не найдена"
    fi
    
    return 0
}

# Основная функция
main() {
    echo "🔗 Тестирование MASQUE функциональности CloudBridge"
    echo "===================================================="
    
    local exit_code=0
    
    # Проверка MASQUE конфигурации
    check_masque_config || exit_code=1
    
    # Проверка mTLS сертификатов
    check_mtls_certs || exit_code=1
    
    # Проверка MASQUE контекстов для каждого региона
    check_masque_contexts "mow" || exit_code=1
    check_masque_contexts "fra" || exit_code=1
    check_masque_contexts "ams" || exit_code=1
    
    # Проверка MASQUE метрик
    check_masque_metrics "mow" || exit_code=1
    check_masque_metrics "fra" || exit_code=1
    check_masque_metrics "ams" || exit_code=1
    
    # Проверка соседей
    check_masque_neighbors "mow" || exit_code=1
    check_masque_neighbors "fra" || exit_code=1
    check_masque_neighbors "ams" || exit_code=1
    
    # Проверка безопасности
    check_masque_security || exit_code=1
    
    # Итоговый результат
    if [ $exit_code -eq 0 ]; then
        success "✅ Все тесты MASQUE прошли успешно!"
    else
        error "❌ Некоторые тесты MASQUE не прошли"
    fi
    
    echo ""
    echo "📊 MASQUE статус:"
    kubectl get configmap masque-config -n cloudbridge-relay
    kubectl get secret cb-interpop-cert -n cloudbridge-relay
    kubectl get networkpolicy relay-network-policy -n cloudbridge-relay
    
    echo ""
    echo "🔍 Полезные команды:"
    echo "  - MASQUE конфигурация: kubectl get configmap masque-config -n cloudbridge-relay -o yaml"
    echo "  - mTLS сертификаты: kubectl get secret cb-interpop-cert -n cloudbridge-relay -o yaml"
    echo "  - Network Policies: kubectl get networkpolicies -n cloudbridge-relay"
    echo "  - MASQUE API: kubectl port-forward -n cloudbridge-relay svc/relay-mow 9090:9090"
    
    exit $exit_code
}

# Запуск основной функции
main "$@"


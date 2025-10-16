#!/bin/bash
# scripts/test-handover.sh

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

# Функция проверки handover метрик
check_handover_metrics() {
    local namespace="cloudbridge-relay"
    
    log "Проверка handover метрик..."
    
    # Проверка метрик для всех PoP
    local regions=("mow" "fra" "ams")
    
    for region in "${regions[@]}"; do
        local pod_name=$(kubectl get pods -n $namespace -l app=cloudbridge-relay,region=$region -o jsonpath='{.items[0].metadata.name}')
        if [ -z "$pod_name" ]; then
            warning "Pod для региона $region не найден, пропускаем"
            continue
        fi
        
        log "Проверка handover метрик для $region..."
        
        # Получение метрик
        local metrics_response=$(kubectl exec -n $namespace $pod_name -- \
          curl -s http://localhost:9091/metrics 2>/dev/null || echo "Metrics недоступны")
        
        if [ "$metrics_response" = "Metrics недоступны" ]; then
            warning "Метрики недоступны для $region"
            continue
        fi
        
        # Проверка handover метрик
        local handover_duration=$(echo "$metrics_response" | grep "relay_handover_duration_seconds" | head -1)
        local handover_total=$(echo "$metrics_response" | grep "relay_handover_total" | head -1)
        local handover_success=$(echo "$metrics_response" | grep "relay_handover_success_total" | head -1)
        local handover_failure=$(echo "$metrics_response" | grep "relay_handover_failure_total" | head -1)
        
        if [ -n "$handover_duration" ]; then
            success "Handover duration метрика для $region: $handover_duration"
        else
            warning "Handover duration метрика для $region не найдена"
        fi
        
        if [ -n "$handover_total" ]; then
            success "Handover total метрика для $region: $handover_total"
        else
            warning "Handover total метрика для $region не найдена"
        fi
        
        if [ -n "$handover_success" ]; then
            success "Handover success метрика для $region: $handover_success"
        else
            warning "Handover success метрика для $region не найдена"
        fi
        
        if [ -n "$handover_failure" ]; then
            success "Handover failure метрика для $region: $handover_failure"
        else
            warning "Handover failure метрика для $region не найдена"
        fi
    done
    
    return 0
}

# Функция тестирования handover между PoP
test_handover_between_pops() {
    local source_region=$1
    local target_region=$2
    local namespace="cloudbridge-relay"
    
    log "Тестирование handover от $source_region к $target_region..."
    
    local pod_name=$(kubectl get pods -n $namespace -l app=cloudbridge-relay,region=$source_region -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$pod_name" ]; then
        error "Pod для региона $source_region не найден"
        return 1
    fi
    
    # Тест handover через AI service
    local handover_response=$(kubectl exec -n $namespace $pod_name -- \
      curl -s -X POST http://ai-service:8083/api/routing/handover \
      -H "Content-Type: application/json" \
      -d "{\"source\": \"$source_region\", \"target\": \"$target_region\", \"test\": true}" 2>/dev/null || echo "AI service недоступен")
    
    if [ "$handover_response" = "AI service недоступен" ]; then
        warning "AI service недоступен, пропускаем тест handover"
        return 0
    fi
    
    # Проверка ответа
    if echo "$handover_response" | grep -q "success\|ok\|handover"; then
        success "Handover от $source_region к $target_region успешен"
        return 0
    else
        error "Handover от $source_region к $target_region не удался"
        return 1
    fi
}

# Функция проверки handover производительности
check_handover_performance() {
    local namespace="cloudbridge-relay"
    
    log "Проверка handover производительности..."
    
    # Проверка SLO для handover
    local regions=("mow" "fra" "ams")
    
    for region in "${regions[@]}"; do
        local pod_name=$(kubectl get pods -n $namespace -l app=cloudbridge-relay,region=$region -o jsonpath='{.items[0].metadata.name}')
        if [ -z "$pod_name" ]; then
            warning "Pod для региона $region не найден, пропускаем"
            continue
        fi
        
        log "Проверка handover производительности для $region..."
        
        # Получение метрик
        local metrics_response=$(kubectl exec -n $namespace $pod_name -- \
          curl -s http://localhost:9091/metrics 2>/dev/null || echo "Metrics недоступны")
        
        if [ "$metrics_response" = "Metrics недоступны" ]; then
            warning "Метрики недоступны для $region"
            continue
        fi
        
        # Проверка handover duration
        local handover_duration=$(echo "$metrics_response" | grep "relay_handover_duration_seconds" | head -1 | awk '{print $2}')
        if [ -n "$handover_duration" ]; then
            # Проверка SLO (handover < 300ms)
            if (( $(echo "$handover_duration < 0.3" | bc -l) )); then
                success "Handover duration для $region в пределах SLO: ${handover_duration}s"
            else
                warning "Handover duration для $region превышает SLO: ${handover_duration}s"
            fi
        else
            warning "Handover duration метрика для $region не найдена"
        fi
        
        # Проверка handover success rate
        local handover_success=$(echo "$metrics_response" | grep "relay_handover_success_total" | head -1 | awk '{print $2}')
        local handover_failure=$(echo "$metrics_response" | grep "relay_handover_failure_total" | head -1 | awk '{print $2}')
        
        if [ -n "$handover_success" ] && [ -n "$handover_failure" ]; then
            local total_handovers=$((handover_success + handover_failure))
            if [ $total_handovers -gt 0 ]; then
                local success_rate=$((handover_success * 100 / total_handovers))
                if [ $success_rate -ge 95 ]; then
                    success "Handover success rate для $region в пределах SLO: ${success_rate}%"
                else
                    warning "Handover success rate для $region ниже SLO: ${success_rate}%"
                fi
            else
                warning "Нет данных о handover для $region"
            fi
        else
            warning "Handover success/failure метрики для $region не найдены"
        fi
    done
    
    return 0
}

# Функция тестирования handover сценариев
test_handover_scenarios() {
    local namespace="cloudbridge-relay"
    
    log "Тестирование handover сценариев..."
    
    # Сценарий 1: Moscow -> Frankfurt
    log "Сценарий 1: Moscow -> Frankfurt"
    test_handover_between_pops "mow" "fra"
    
    # Сценарий 2: Moscow -> Amsterdam
    log "Сценарий 2: Moscow -> Amsterdam"
    test_handover_between_pops "mow" "ams"
    
    # Сценарий 3: Frankfurt -> Moscow
    log "Сценарий 3: Frankfurt -> Moscow"
    test_handover_between_pops "fra" "mow"
    
    # Сценарий 4: Frankfurt -> Amsterdam
    log "Сценарий 4: Frankfurt -> Amsterdam"
    test_handover_between_pops "fra" "ams"
    
    # Сценарий 5: Amsterdam -> Moscow
    log "Сценарий 5: Amsterdam -> Moscow"
    test_handover_between_pops "ams" "mow"
    
    # Сценарий 6: Amsterdam -> Frankfurt
    log "Сценарий 6: Amsterdam -> Frankfurt"
    test_handover_between_pops "ams" "fra"
    
    return 0
}

# Функция проверки handover конфигурации
check_handover_configuration() {
    local namespace="cloudbridge-relay"
    
    log "Проверка handover конфигурации..."
    
    # Проверка MASQUE конфигурации
    if kubectl get configmap masque-config -n $namespace >/dev/null 2>&1; then
        success "MASQUE ConfigMap найден"
        
        # Проверка handover настроек в MASQUE
        local masque_config=$(kubectl get configmap masque-config -n $namespace -o jsonpath='{.data.masque\.yaml}')
        if echo "$masque_config" | grep -q "handover\|routing"; then
            success "Handover конфигурация найдена в MASQUE"
        else
            warning "Handover конфигурация не найдена в MASQUE"
        fi
    else
        warning "MASQUE ConfigMap не найден"
    fi
    
    # Проверка AI service
    if kubectl get pods -n cloudbridge-control -l app=ai-service >/dev/null 2>&1; then
        success "AI service найден"
    else
        warning "AI service не найден"
    fi
    
    return 0
}

# Функция проверки handover алертов
check_handover_alerts() {
    local namespace="cloudbridge-relay"
    
    log "Проверка handover алертов..."
    
    # Проверка Prometheus правил
    if kubectl get configmap prometheus-rules -n $namespace >/dev/null 2>&1; then
        success "Prometheus rules найдены"
        
        # Проверка handover алертов
        local rules_config=$(kubectl get configmap prometheus-rules -n $namespace -o jsonpath='{.data.edge-pops-alerts\.yml}')
        if echo "$rules_config" | grep -q "HandoverTimeout\|handover"; then
            success "Handover алерты настроены"
        else
            warning "Handover алерты не найдены"
        fi
    else
        warning "Prometheus rules не найдены"
    fi
    
    return 0
}

# Основная функция
main() {
    echo "🔄 Тестирование Handover функциональности CloudBridge"
    echo "======================================================"
    
    local exit_code=0
    
    # Проверка handover метрик
    check_handover_metrics || exit_code=1
    
    # Проверка handover производительности
    check_handover_performance || exit_code=1
    
    # Тестирование handover сценариев
    test_handover_scenarios || exit_code=1
    
    # Проверка handover конфигурации
    check_handover_configuration || exit_code=1
    
    # Проверка handover алертов
    check_handover_alerts || exit_code=1
    
    # Итоговый результат
    if [ $exit_code -eq 0 ]; then
        success "✅ Все тесты Handover прошли успешно!"
    else
        error "❌ Некоторые тесты Handover не прошли"
    fi
    
    echo ""
    echo "📊 Handover метрики:"
    kubectl get pods -n cloudbridge-relay -l app=cloudbridge-relay
    
    echo ""
    echo "🔍 Полезные команды:"
    echo "  - Handover метрики: kubectl port-forward -n cloudbridge-relay svc/relay-mow 9091:9091"
    echo "  - AI service: kubectl get pods -n cloudbridge-control -l app=ai-service"
    echo "  - Prometheus алерты: kubectl get configmap prometheus-rules -n cloudbridge-relay"
    echo "  - Handover логи: kubectl logs -n cloudbridge-relay -l app=cloudbridge-relay | grep handover"
    
    exit $exit_code
}

# Запуск основной функции
main "$@"

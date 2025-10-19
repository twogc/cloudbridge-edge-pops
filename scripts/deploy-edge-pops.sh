#!/bin/bash
# scripts/deploy-edge-pops.sh

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для логирования
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

# Функция проверки health
check_health() {
    local deployment=$1
    local namespace=$2
    local timeout=${3:-300}
    
    log "Проверка health для deployment: $deployment"
    
    # Проверка rollout status
    if ! kubectl rollout status deployment/$deployment -n $namespace --timeout=${timeout}s; then
        error "Deployment $deployment не готов в течение ${timeout}s"
        return 1
    fi
    
    # Проверка готовности подов
    if ! kubectl wait --for=condition=ready pod -l app=cloudbridge-relay -n $namespace --timeout=${timeout}s; then
        error "Pods для $deployment не готовы в течение ${timeout}s"
        return 1
    fi
    
    # Проверка health endpoints
    local pod_name=$(kubectl get pods -n $namespace -l app=cloudbridge-relay -o jsonpath='{.items[0].metadata.name}')
    if [ -n "$pod_name" ]; then
        log "Проверка health endpoint для $pod_name"
        if ! kubectl exec -n $namespace $pod_name -- curl -f http://localhost:9091/health >/dev/null 2>&1; then
            warning "Health endpoint недоступен для $pod_name, но deployment готов"
        else
            success "Health endpoint доступен для $pod_name"
        fi
    fi
    
    return 0
}

# Функция проверки связности
check_connectivity() {
    local source_region=$1
    local target_regions=$2
    
    log "Проверка связности от $source_region к $target_regions"
    
    local pod_name=$(kubectl get pods -n cloudbridge-relay -l app=cloudbridge-relay,region=$source_region -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$pod_name" ]; then
        error "Pod для региона $source_region не найден"
        return 1
    fi
    
    # Проверка связности через AI service (если доступен)
    if kubectl exec -n cloudbridge-relay $pod_name -- curl -f http://ai-service:8083/health >/dev/null 2>&1; then
        log "AI service доступен, проверяем связность"
        kubectl exec -n cloudbridge-relay $pod_name -- \
          curl -X POST http://ai-service:8083/api/routing/test-connectivity \
          -H "Content-Type: application/json" \
          -d "{\"source\": \"$source_region\", \"targets\": [$target_regions]}" || warning "AI service связность недоступна"
    else
        warning "AI service недоступен, пропускаем проверку связности"
    fi
    
    return 0
}

echo "🌍 Развертывание CloudBridge Edge PoP Nodes"
echo "=============================================="

# 1. Создание namespace
log "Создание namespace cloudbridge-relay..."
kubectl create namespace cloudbridge-relay --dry-run=client -o yaml | kubectl apply -f -
success "Namespace cloudbridge-relay создан"

# 2. Развертывание Moscow PoP
log "Развертывание Moscow PoP..."
kubectl apply -f k8s/relay-mow/
success "Moscow PoP конфигурация применена"

# 3. Ожидание готовности Moscow PoP
log "Ожидание готовности Moscow PoP..."
if check_health "cloudbridge-relay" "cloudbridge-relay" 300; then
    success "Moscow PoP готов"
else
    error "Moscow PoP не готов"
    exit 1
fi

# 4. Развертывание Frankfurt PoP
log "Развертывание Frankfurt PoP..."
kubectl apply -f k8s/relay-fra/
success "Frankfurt PoP конфигурация применена"

# 5. Ожидание готовности Frankfurt PoP
log "Ожидание готовности Frankfurt PoP..."
if check_health "cloudbridge-relay" "cloudbridge-relay" 300; then
    success "Frankfurt PoP готов"
else
    error "Frankfurt PoP не готов"
    exit 1
fi

# 6. Развертывание Amsterdam PoP
log "Развертывание Amsterdam PoP..."
kubectl apply -f k8s/relay-ams/
success "Amsterdam PoP конфигурация применена"

# 7. Ожидание готовности Amsterdam PoP
log "Ожидание готовности Amsterdam PoP..."
if check_health "cloudbridge-relay" "cloudbridge-relay" 300; then
    success "Amsterdam PoP готов"
else
    error "Amsterdam PoP не готов"
    exit 1
fi

# 8. Настройка Inter-PoP MASQUE
log "Настройка Inter-PoP MASQUE..."
kubectl apply -f masque/
success "MASQUE конфигурация применена"

# 9. Настройка мониторинга
log "Настройка мониторинга..."
kubectl apply -f monitoring/
success "Мониторинг настроен"

# 10. Проверка связности
log "Проверка Inter-PoP связности..."
check_connectivity "mow" '["fra", "ams"]'
check_connectivity "fra" '["mow", "ams"]'
check_connectivity "ams" '["mow", "fra"]'

# 11. Финальная проверка готовности
log "Финальная проверка готовности Edge PoP Nodes..."
kubectl get pods -n cloudbridge-relay

# 12. Проверка сервисов
log "Проверка сервисов..."
kubectl get services -n cloudbridge-relay

# 13. Проверка Network Policies
log "Проверка Network Policies..."
kubectl get networkpolicies -n cloudbridge-relay

success "🎉 Edge PoP Nodes развернуты успешно!"
echo ""
echo "📊 Доступные PoP узлы:"
echo "  - Moscow PoP: kubectl get pods -n cloudbridge-relay -l region=mow"
echo "  - Frankfurt PoP: kubectl get pods -n cloudbridge-relay -l region=fra"
echo "  - Amsterdam PoP: kubectl get pods -n cloudbridge-relay -l region=ams"
echo ""
echo "🔍 Полезные команды:"
echo "  - Статус: kubectl get all -n cloudbridge-relay"
echo "  - Логи: kubectl logs -n cloudbridge-relay -l app=cloudbridge-relay"
echo "  - Метрики: kubectl port-forward -n cloudbridge-relay svc/relay-mow 9091:9091"
echo "  - Тест связности: ./scripts/test-inter-pop-connectivity.sh"











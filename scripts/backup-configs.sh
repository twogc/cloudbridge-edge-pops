#!/bin/bash
# scripts/backup-configs.sh

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

# Конфигурация
BACKUP_DIR="/tmp/cloudbridge-backup-$(date +%Y%m%d-%H%M%S)"
NAMESPACES=("cloudbridge-relay" "cloudbridge-control" "cert-manager")
KINDS=("deployments" "services" "configmaps" "secrets" "networkpolicies" "certificates" "clusterissuers")

# Функция создания backup директории
create_backup_dir() {
    log "Создание backup директории: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    success "Backup директория создана: $BACKUP_DIR"
}

# Функция backup namespace
backup_namespace() {
    local namespace=$1
    
    log "Backup namespace: $namespace"
    mkdir -p "$BACKUP_DIR/$namespace"
    
    # Backup всех ресурсов в namespace
    for kind in "${KINDS[@]}"; do
        log "Backup $kind в namespace $namespace"
        
        # Получение списка ресурсов
        local resources=$(kubectl get $kind -n $namespace --no-headers -o custom-columns=":metadata.name" 2>/dev/null || echo "")
        
        if [ -n "$resources" ]; then
            for resource in $resources; do
                log "Backup $kind/$resource"
                kubectl get $kind $resource -n $namespace -o yaml > "$BACKUP_DIR/$namespace/$kind-$resource.yaml" 2>/dev/null || warning "Не удалось backup $kind/$resource"
            done
        else
            warning "Нет ресурсов типа $kind в namespace $namespace"
        fi
    done
    
    success "Backup namespace $namespace завершен"
}

# Функция backup cluster-wide ресурсов
backup_cluster_resources() {
    log "Backup cluster-wide ресурсов"
    mkdir -p "$BACKUP_DIR/cluster"
    
    # Backup ClusterIssuers
    kubectl get clusterissuers -o yaml > "$BACKUP_DIR/cluster/clusterissuers.yaml" 2>/dev/null || warning "Не удалось backup ClusterIssuers"
    
    # Backup GlobalNetworkPolicies
    kubectl get globalnetworkpolicies -o yaml > "$BACKUP_DIR/cluster/globalnetworkpolicies.yaml" 2>/dev/null || warning "Не удалось backup GlobalNetworkPolicies"
    
    # Backup Nodes
    kubectl get nodes -o yaml > "$BACKUP_DIR/cluster/nodes.yaml" 2>/dev/null || warning "Не удалось backup Nodes"
    
    success "Backup cluster-wide ресурсов завершен"
}

# Функция backup конфигурационных файлов
backup_config_files() {
    log "Backup конфигурационных файлов"
    mkdir -p "$BACKUP_DIR/configs"
    
    # Backup MASQUE конфигурации
    if [ -d "masque" ]; then
        cp -r masque "$BACKUP_DIR/configs/"
        success "MASQUE конфигурации скопированы"
    else
        warning "Папка masque не найдена"
    fi
    
    # Backup Kubernetes конфигурации
    if [ -d "k8s" ]; then
        cp -r k8s "$BACKUP_DIR/configs/"
        success "Kubernetes конфигурации скопированы"
    else
        warning "Папка k8s не найдена"
    fi
    
    # Backup мониторинг конфигурации
    if [ -d "monitoring" ]; then
        cp -r monitoring "$BACKUP_DIR/configs/"
        success "Мониторинг конфигурации скопированы"
    else
        warning "Папка monitoring не найдена"
    fi
    
    # Backup AI routing конфигурации
    if [ -d "ai-routing" ]; then
        cp -r ai-routing "$BACKUP_DIR/configs/"
        success "AI routing конфигурации скопированы"
    else
        warning "Папка ai-routing не найдена"
    fi
    
    # Backup скриптов
    if [ -d "scripts" ]; then
        cp -r scripts "$BACKUP_DIR/configs/"
        success "Скрипты скопированы"
    else
        warning "Папка scripts не найдена"
    fi
    
    # Backup документации
    if [ -d "docs" ]; then
        cp -r docs "$BACKUP_DIR/configs/"
        success "Документация скопирована"
    else
        warning "Папка docs не найдена"
    fi
}

# Функция создания архива
create_archive() {
    log "Создание архива backup"
    local archive_name="cloudbridge-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    cd "$(dirname "$BACKUP_DIR")"
    tar -czf "$archive_name" "$(basename "$BACKUP_DIR")"
    
    if [ $? -eq 0 ]; then
        success "Архив создан: $archive_name"
        echo "Архив находится в: $(pwd)/$archive_name"
    else
        error "Не удалось создать архив"
        return 1
    fi
}

# Функция очистки временных файлов
cleanup() {
    log "Очистка временных файлов"
    rm -rf "$BACKUP_DIR"
    success "Временные файлы очищены"
}

# Функция проверки зависимостей
check_dependencies() {
    log "Проверка зависимостей"
    
    # Проверка kubectl
    if ! command -v kubectl &> /dev/null; then
        error "kubectl не найден"
        return 1
    fi
    
    # Проверка подключения к кластеру
    if ! kubectl cluster-info &> /dev/null; then
        error "Не удалось подключиться к кластеру"
        return 1
    fi
    
    # Проверка tar
    if ! command -v tar &> /dev/null; then
        error "tar не найден"
        return 1
    fi
    
    success "Все зависимости проверены"
}

# Функция создания отчета
create_report() {
    log "Создание отчета backup"
    local report_file="$BACKUP_DIR/backup-report.txt"
    
    cat > "$report_file" << EOF
CloudBridge Edge PoP Backup Report
==================================
Date: $(date)
Backup Directory: $BACKUP_DIR

Namespaces:
$(for ns in "${NAMESPACES[@]}"; do echo "- $ns"; done)

Resources backed up:
$(for kind in "${KINDS[@]}"; do echo "- $kind"; done)

Backup Contents:
$(find "$BACKUP_DIR" -type f -name "*.yaml" | wc -l) YAML files
$(find "$BACKUP_DIR" -type d | wc -l) directories

Cluster Info:
$(kubectl cluster-info)

Node Info:
$(kubectl get nodes --no-headers | wc -l) nodes

EOF
    
    success "Отчет создан: $report_file"
}

# Основная функция
main() {
    echo "💾 CloudBridge Edge PoP Backup"
    echo "==============================="
    
    # Проверка зависимостей
    check_dependencies || exit 1
    
    # Создание backup директории
    create_backup_dir || exit 1
    
    # Backup каждого namespace
    for namespace in "${NAMESPACES[@]}"; do
        if kubectl get namespace $namespace &> /dev/null; then
            backup_namespace $namespace
        else
            warning "Namespace $namespace не найден, пропускаем"
        fi
    done
    
    # Backup cluster-wide ресурсов
    backup_cluster_resources
    
    # Backup конфигурационных файлов
    backup_config_files
    
    # Создание отчета
    create_report
    
    # Создание архива
    create_archive || exit 1
    
    # Очистка
    cleanup
    
    success "🎉 Backup завершен успешно!"
    echo ""
    echo "📊 Статистика backup:"
    echo "  - Namespaces: ${#NAMESPACES[@]}"
    echo "  - Resource types: ${#KINDS[@]}"
    echo "  - Archive: cloudbridge-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    echo ""
    echo "🔍 Полезные команды:"
    echo "  - Восстановление: ./scripts/restore-configs.sh <archive>"
    echo "  - Просмотр архива: tar -tzf cloudbridge-backup-*.tar.gz"
    echo "  - Извлечение: tar -xzf cloudbridge-backup-*.tar.gz"
}

# Запуск основной функции
main "$@"

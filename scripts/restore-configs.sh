#!/bin/bash
# scripts/restore-configs.sh

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

# Функция проверки параметров
check_parameters() {
    if [ $# -eq 0 ]; then
        error "Не указан архив для восстановления"
        echo "Использование: $0 <archive-file>"
        echo "Пример: $0 cloudbridge-backup-20240101-120000.tar.gz"
        exit 1
    fi
    
    local archive_file=$1
    
    if [ ! -f "$archive_file" ]; then
        error "Архив не найден: $archive_file"
        exit 1
    fi
    
    if [[ ! "$archive_file" =~ \.tar\.gz$ ]]; then
        error "Архив должен быть в формате .tar.gz"
        exit 1
    fi
    
    success "Архив найден: $archive_file"
}

# Функция извлечения архива
extract_archive() {
    local archive_file=$1
    local extract_dir="/tmp/cloudbridge-restore-$(date +%Y%m%d-%H%M%S)"
    
    log "Извлечение архива: $archive_file"
    mkdir -p "$extract_dir"
    
    if tar -xzf "$archive_file" -C "$extract_dir"; then
        success "Архив извлечен в: $extract_dir"
        echo "$extract_dir"
    else
        error "Не удалось извлечь архив"
        exit 1
    fi
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

# Функция создания namespace
create_namespace() {
    local namespace=$1
    
    log "Создание namespace: $namespace"
    
    if kubectl get namespace $namespace &> /dev/null; then
        warning "Namespace $namespace уже существует"
    else
        kubectl create namespace $namespace
        success "Namespace $namespace создан"
    fi
}

# Функция восстановления namespace
restore_namespace() {
    local namespace=$1
    local restore_dir=$2
    
    log "Восстановление namespace: $namespace"
    
    if [ ! -d "$restore_dir/$namespace" ]; then
        warning "Папка $namespace не найдена в backup, пропускаем"
        return 0
    fi
    
    # Создание namespace если не существует
    create_namespace $namespace
    
    # Восстановление ресурсов
    local resource_files=$(find "$restore_dir/$namespace" -name "*.yaml" -type f)
    
    if [ -z "$resource_files" ]; then
        warning "Нет YAML файлов для восстановления в namespace $namespace"
        return 0
    fi
    
    for file in $resource_files; do
        local filename=$(basename "$file")
        log "Восстановление $filename"
        
        if kubectl apply -f "$file" &> /dev/null; then
            success "Восстановлен $filename"
        else
            warning "Не удалось восстановить $filename"
        fi
    done
    
    success "Namespace $namespace восстановлен"
}

# Функция восстановления cluster-wide ресурсов
restore_cluster_resources() {
    local restore_dir=$1
    
    log "Восстановление cluster-wide ресурсов"
    
    if [ ! -d "$restore_dir/cluster" ]; then
        warning "Папка cluster не найдена в backup, пропускаем"
        return 0
    fi
    
    local cluster_files=$(find "$restore_dir/cluster" -name "*.yaml" -type f)
    
    if [ -z "$cluster_files" ]; then
        warning "Нет cluster-wide YAML файлов для восстановления"
        return 0
    fi
    
    for file in $cluster_files; do
        local filename=$(basename "$file")
        log "Восстановление cluster resource $filename"
        
        if kubectl apply -f "$file" &> /dev/null; then
            success "Восстановлен cluster resource $filename"
        else
            warning "Не удалось восстановить cluster resource $filename"
        fi
    done
    
    success "Cluster-wide ресурсы восстановлены"
}

# Функция восстановления конфигурационных файлов
restore_config_files() {
    local restore_dir=$1
    
    log "Восстановление конфигурационных файлов"
    
    if [ ! -d "$restore_dir/configs" ]; then
        warning "Папка configs не найдена в backup, пропускаем"
        return 0
    fi
    
    # Восстановление MASQUE конфигурации
    if [ -d "$restore_dir/configs/masque" ]; then
        if [ -d "masque" ]; then
            warning "Папка masque уже существует, создаем backup"
            mv masque masque.backup.$(date +%Y%m%d-%H%M%S)
        fi
        cp -r "$restore_dir/configs/masque" .
        success "MASQUE конфигурации восстановлены"
    else
        warning "MASQUE конфигурации не найдены в backup"
    fi
    
    # Восстановление Kubernetes конфигурации
    if [ -d "$restore_dir/configs/k8s" ]; then
        if [ -d "k8s" ]; then
            warning "Папка k8s уже существует, создаем backup"
            mv k8s k8s.backup.$(date +%Y%m%d-%H%M%S)
        fi
        cp -r "$restore_dir/configs/k8s" .
        success "Kubernetes конфигурации восстановлены"
    else
        warning "Kubernetes конфигурации не найдены в backup"
    fi
    
    # Восстановление мониторинг конфигурации
    if [ -d "$restore_dir/configs/monitoring" ]; then
        if [ -d "monitoring" ]; then
            warning "Папка monitoring уже существует, создаем backup"
            mv monitoring monitoring.backup.$(date +%Y%m%d-%H%M%S)
        fi
        cp -r "$restore_dir/configs/monitoring" .
        success "Мониторинг конфигурации восстановлены"
    else
        warning "Мониторинг конфигурации не найдены в backup"
    fi
    
    # Восстановление AI routing конфигурации
    if [ -d "$restore_dir/configs/ai-routing" ]; then
        if [ -d "ai-routing" ]; then
            warning "Папка ai-routing уже существует, создаем backup"
            mv ai-routing ai-routing.backup.$(date +%Y%m%d-%H%M%S)
        fi
        cp -r "$restore_dir/configs/ai-routing" .
        success "AI routing конфигурации восстановлены"
    else
        warning "AI routing конфигурации не найдены в backup"
    fi
    
    # Восстановление скриптов
    if [ -d "$restore_dir/configs/scripts" ]; then
        if [ -d "scripts" ]; then
            warning "Папка scripts уже существует, создаем backup"
            mv scripts scripts.backup.$(date +%Y%m%d-%H%M%S)
        fi
        cp -r "$restore_dir/configs/scripts" .
        success "Скрипты восстановлены"
    else
        warning "Скрипты не найдены в backup"
    fi
    
    # Восстановление документации
    if [ -d "$restore_dir/configs/docs" ]; then
        if [ -d "docs" ]; then
            warning "Папка docs уже существует, создаем backup"
            mv docs docs.backup.$(date +%Y%m%d-%H%M%S)
        fi
        cp -r "$restore_dir/configs/docs" .
        success "Документация восстановлена"
    else
        warning "Документация не найдена в backup"
    fi
}

# Функция проверки восстановления
verify_restore() {
    local restore_dir=$1
    
    log "Проверка восстановления"
    
    # Проверка namespace
    local namespaces=("cloudbridge-relay" "cloudbridge-control" "cert-manager")
    for namespace in "${namespaces[@]}"; do
        if kubectl get namespace $namespace &> /dev/null; then
            success "Namespace $namespace существует"
        else
            warning "Namespace $namespace не найден"
        fi
    done
    
    # Проверка deployments
    if kubectl get deployments -n cloudbridge-relay &> /dev/null; then
        local deployment_count=$(kubectl get deployments -n cloudbridge-relay --no-headers | wc -l)
        success "Найдено $deployment_count deployments в cloudbridge-relay"
    else
        warning "Deployments в cloudbridge-relay не найдены"
    fi
    
    # Проверка services
    if kubectl get services -n cloudbridge-relay &> /dev/null; then
        local service_count=$(kubectl get services -n cloudbridge-relay --no-headers | wc -l)
        success "Найдено $service_count services в cloudbridge-relay"
    else
        warning "Services в cloudbridge-relay не найдены"
    fi
    
    # Проверка configmaps
    if kubectl get configmaps -n cloudbridge-relay &> /dev/null; then
        local configmap_count=$(kubectl get configmaps -n cloudbridge-relay --no-headers | wc -l)
        success "Найдено $configmap_count configmaps в cloudbridge-relay"
    else
        warning "ConfigMaps в cloudbridge-relay не найдены"
    fi
}

# Функция очистки временных файлов
cleanup() {
    local restore_dir=$1
    
    log "Очистка временных файлов"
    rm -rf "$restore_dir"
    success "Временные файлы очищены"
}

# Функция создания отчета восстановления
create_restore_report() {
    local restore_dir=$1
    local report_file="$restore_dir/restore-report.txt"
    
    log "Создание отчета восстановления"
    
    cat > "$report_file" << EOF
CloudBridge Edge PoP Restore Report
===================================
Date: $(date)
Restore Directory: $restore_dir

Namespaces:
$(kubectl get namespaces --no-headers | grep -E "(cloudbridge|cert-manager)" | awk '{print "- " $1}')

Deployments:
$(kubectl get deployments -n cloudbridge-relay --no-headers | awk '{print "- " $1}')

Services:
$(kubectl get services -n cloudbridge-relay --no-headers | awk '{print "- " $1}')

ConfigMaps:
$(kubectl get configmaps -n cloudbridge-relay --no-headers | awk '{print "- " $1}')

Secrets:
$(kubectl get secrets -n cloudbridge-relay --no-headers | awk '{print "- " $1}')

Network Policies:
$(kubectl get networkpolicies -n cloudbridge-relay --no-headers | awk '{print "- " $1}')

Cluster Info:
$(kubectl cluster-info)

EOF
    
    success "Отчет восстановления создан: $report_file"
}

# Основная функция
main() {
    echo "🔄 CloudBridge Edge PoP Restore"
    echo "================================"
    
    # Проверка параметров
    check_parameters "$@"
    
    local archive_file=$1
    
    # Проверка зависимостей
    check_dependencies || exit 1
    
    # Извлечение архива
    local restore_dir=$(extract_archive "$archive_file")
    
    # Восстановление namespace
    local namespaces=("cloudbridge-relay" "cloudbridge-control" "cert-manager")
    for namespace in "${namespaces[@]}"; do
        restore_namespace $namespace "$restore_dir"
    done
    
    # Восстановление cluster-wide ресурсов
    restore_cluster_resources "$restore_dir"
    
    # Восстановление конфигурационных файлов
    restore_config_files "$restore_dir"
    
    # Проверка восстановления
    verify_restore "$restore_dir"
    
    # Создание отчета
    create_restore_report "$restore_dir"
    
    # Очистка
    cleanup "$restore_dir"
    
    success "🎉 Восстановление завершено успешно!"
    echo ""
    echo "📊 Статистика восстановления:"
    echo "  - Namespaces: ${#namespaces[@]}"
    echo "  - Archive: $archive_file"
    echo ""
    echo "🔍 Полезные команды:"
    echo "  - Статус: kubectl get all -n cloudbridge-relay"
    echo "  - Логи: kubectl logs -n cloudbridge-relay -l app=cloudbridge-relay"
    echo "  - Тест: ./scripts/test-inter-pop-connectivity.sh"
    echo "  - Развертывание: ./scripts/deploy-edge-pops.sh"
}

# Запуск основной функции
main "$@"

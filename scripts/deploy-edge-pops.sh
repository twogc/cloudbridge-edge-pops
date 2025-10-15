#!/bin/bash
# scripts/deploy-edge-pops.sh

set -e

echo "🌍 Развертывание CloudBridge Edge PoP Nodes"

# 1. Создание namespace
echo "📦 Создание namespace..."
kubectl create namespace cloudbridge-relay --dry-run=client -o yaml | kubectl apply -f -

# 2. Развертывание Moscow PoP
echo "🏢 Развертывание Moscow PoP..."
kubectl apply -f k8s/relay-mow/

# 3. Ожидание готовности Moscow PoP
echo "⏳ Ожидание готовности Moscow PoP..."
kubectl wait --for=condition=ready pod -l app=cloudbridge-relay,region=mow -n cloudbridge-relay --timeout=300s

# 4. Развертывание Frankfurt PoP
echo "🏢 Развертывание Frankfurt PoP..."
kubectl apply -f k8s/relay-fra/

# 5. Ожидание готовности Frankfurt PoP
echo "⏳ Ожидание готовности Frankfurt PoP..."
kubectl wait --for=condition=ready pod -l app=cloudbridge-relay,region=fra -n cloudbridge-relay --timeout=300s

# 6. Развертывание Amsterdam PoP
echo "🏢 Развертывание Amsterdam PoP..."
kubectl apply -f k8s/relay-ams/

# 7. Ожидание готовности Amsterdam PoP
echo "⏳ Ожидание готовности Amsterdam PoP..."
kubectl wait --for=condition=ready pod -l app=cloudbridge-relay,region=ams -n cloudbridge-relay --timeout=300s

# 8. Настройка Inter-PoP MASQUE
echo "🔗 Настройка Inter-PoP MASQUE..."
kubectl apply -f masque/

# 9. Проверка готовности
echo "✅ Проверка готовности Edge PoP Nodes..."
kubectl get pods -n cloudbridge-relay

echo "🎉 Edge PoP Nodes развернуты успешно!"
echo ""
echo "📊 Доступные PoP узлы:"
echo "  - Moscow PoP: kubectl get pods -n cloudbridge-relay -l region=mow"
echo "  - Frankfurt PoP: kubectl get pods -n cloudbridge-relay -l region=fra"
echo "  - Amsterdam PoP: kubectl get pods -n cloudbridge-relay -l region=ams"

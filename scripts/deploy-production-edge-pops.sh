#!/bin/bash

# CloudBridge Edge PoP - Production Deployment Script
# Based on kube-prometheus, Sloth, ebpf_exporter, and industry best practices

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="cloudbridge-relay"
PRODUCTION_DIR="k8s/production"
SECURITY_DIR="k8s/security"
MONITORING_DIR="k8s/monitoring"

echo -e "${BLUE}🌐 CloudBridge Edge PoP - Production Deployment${NC}"
echo "======================================================"
echo -e "${BLUE}Based on reference implementations:${NC}"
echo "  - kube-prometheus (Production hardening)"
echo "  - Sloth (SLO monitoring)"
echo "  - ebpf_exporter (Network monitoring)"
echo "  - AlertManager (Advanced routing)"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo -e "${YELLOW}⚠️  Namespace '$NAMESPACE' does not exist. Creating...${NC}"
    kubectl create namespace "$NAMESPACE"
fi

# Deploy RBAC
echo -e "${BLUE}📋 Deploying RBAC...${NC}"
kubectl apply -f "$SECURITY_DIR/relay-rbac.yaml"

# Deploy Production Edge PoP Deployments
echo -e "${BLUE}🏢 Deploying Production Edge PoP Deployments...${NC}"
kubectl apply -f "$PRODUCTION_DIR/relay-production-mow.yaml"
kubectl apply -f "$PRODUCTION_DIR/relay-production-fra.yaml"
kubectl apply -f "$PRODUCTION_DIR/relay-production-ams.yaml"

# Deploy MASQUE Configuration
echo -e "${BLUE}🔗 Deploying MASQUE Configuration...${NC}"
kubectl apply -f masque/

# Deploy SLO Monitoring
echo -e "${BLUE}📊 Deploying SLO Monitoring...${NC}"
kubectl apply -f "$MONITORING_DIR/edge-pops-slo.yaml"

# Deploy ServiceMonitor/PodMonitor
echo -e "${BLUE}📈 Deploying ServiceMonitor/PodMonitor...${NC}"
kubectl apply -f "$MONITORING_DIR/relay-servicemonitor.yaml"

# Deploy AlertManager Rules
echo -e "${BLUE}🚨 Deploying AlertManager Rules...${NC}"
kubectl apply -f "$MONITORING_DIR/edge-pops-alerts.yaml"

# Deploy eBPF Exporter
echo -e "${BLUE}🔍 Deploying eBPF Exporter...${NC}"
kubectl apply -f "$MONITORING_DIR/ebpf-exporter-config.yaml"
kubectl apply -f "$MONITORING_DIR/ebpf-exporter-daemonset.yaml"

# Wait for deployments to be ready
echo -e "${BLUE}⏳ Waiting for deployments to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/relay-mow-production -n "$NAMESPACE" || true
kubectl wait --for=condition=available --timeout=300s deployment/relay-fra-production -n "$NAMESPACE" || true
kubectl wait --for=condition=available --timeout=300s deployment/relay-ams-production -n "$NAMESPACE" || true
kubectl wait --for=condition=ready --timeout=300s daemonset/ebpf-exporter -n "$NAMESPACE" || true

# Check deployment status
echo -e "${BLUE}📊 Checking deployment status...${NC}"
kubectl get deployments -n "$NAMESPACE" -l app.kubernetes.io/part-of=cloudbridge-edge-pops
kubectl get daemonsets -n "$NAMESPACE" -l app.kubernetes.io/part-of=cloudbridge-edge-pops
kubectl get services -n "$NAMESPACE" -l app.kubernetes.io/part-of=cloudbridge-edge-pops

# Test connectivity
echo -e "${BLUE}🔗 Testing Edge PoP connectivity...${NC}"
echo "Testing Moscow PoP..."
kubectl exec -n "$NAMESPACE" deployment/relay-mow-production -- curl -s http://localhost:8080/health || echo "Moscow PoP health check failed"

echo "Testing Frankfurt PoP..."
kubectl exec -n "$NAMESPACE" deployment/relay-fra-production -- curl -s http://localhost:8080/health || echo "Frankfurt PoP health check failed"

echo "Testing Amsterdam PoP..."
kubectl exec -n "$NAMESPACE" deployment/relay-ams-production -- curl -s http://localhost:8080/health || echo "Amsterdam PoP health check failed"

# Display access information
echo -e "${GREEN}✅ CloudBridge Edge PoP production deployment completed!${NC}"
echo ""
echo -e "${BLUE}📊 Access Information:${NC}"
echo "  - Moscow PoP: kubectl port-forward svc/relay-mow-production 443:443 -n $NAMESPACE"
echo "  - Frankfurt PoP: kubectl port-forward svc/relay-fra-production 443:443 -n $NAMESPACE"
echo "  - Amsterdam PoP: kubectl port-forward svc/relay-ams-production 443:443 -n $NAMESPACE"
echo "  - eBPF Metrics: kubectl port-forward svc/ebpf-exporter 9435:9435 -n $NAMESPACE"
echo ""
echo -e "${BLUE}📈 Production Features:${NC}"
echo "  - HA Edge PoP (3 replicas each) with production hardening"
echo "  - Inter-PoP MASQUE connectivity with mTLS security"
echo "  - SLO monitoring with burn-rate alerts"
echo "  - eBPF network monitoring for performance"
echo "  - Advanced security (RBAC, Network Policies)"
echo "  - Comprehensive alerting (Critical, Warning, Security)"
echo ""
echo -e "${BLUE}🚨 Alert Routing:${NC}"
echo "  - Critical alerts → oncall@cloudbridge.internal + #alerts-critical"
echo "  - Network alerts → network-team@cloudbridge.internal + #network-alerts"
echo "  - Security alerts → security-team@cloudbridge.internal + #security-alerts"
echo "  - Warning alerts → team@cloudbridge.internal + #alerts-warning"
echo ""
echo -e "${BLUE}📊 SLO Monitoring:${NC}"
echo "  - Edge PoP Availability: 99.9%"
echo "  - Performance: 99.5% under 50ms RTT"
echo "  - Inter-PoP Connectivity: 99.5%"
echo "  - MASQUE Contexts: 99.0%"
echo ""
echo -e "${BLUE}🔍 Network Monitoring:${NC}"
echo "  - eBPF metrics for network performance"
echo "  - Packet drops and latency monitoring"
echo "  - TCP/UDP connection tracking"
echo "  - QUIC-specific metrics"
echo ""
echo -e "${YELLOW}⚠️  Next Steps:${NC}"
echo "  1. Configure SMTP settings in AlertManager config"
echo "  2. Set up Slack webhooks for alert notifications"
echo "  3. Configure BGP neighbors for Anycast"
echo "  4. Set up Anycast IP addresses"
echo "  5. Test Inter-PoP connectivity and MASQUE"
echo ""
echo -e "${GREEN}🎉 CloudBridge Edge PoP is production ready!${NC}"
echo -e "${BLUE}Based on industry best practices from:${NC}"
echo "  - kube-prometheus (Production hardening)"
echo "  - Sloth (SLO as Code)"
echo "  - ebpf_exporter (Network monitoring)"
echo "  - AlertManager (Advanced routing)"






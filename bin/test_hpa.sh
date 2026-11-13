#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

NAMESPACE="default"
SERVICE_NAME="os-service-web"
DEPLOYMENT_LABEL="app=os-service-web"
HPA_NAME="os-service-hpa"
LOAD_GEN_NAME="load-generator"
TARGET_PATH="/up"
DEFAULT_REPLICAS=3
POLL_INTERVAL=5

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}i ${NC}$1"; }
log_success() { echo -e "${GREEN}v ${NC}$1"; }
log_warn()    { echo -e "${YELLOW}! ${NC}$1"; }
log_error()   { echo -e "${RED}x ${NC}$1"; }

COMMAND="${1:-start}"
REPLICAS="${2:-$DEFAULT_REPLICAS}"

check_prereqs() {
  if ! command -v kubectl &>/dev/null; then
    log_error "kubectl não encontrado no PATH."
    exit 1
  fi

  if ! kubectl cluster-info &>/dev/null; then
    log_error "kubectl não conseguiu falar com o cluster. Rode 'aws eks update-kubeconfig --name oficina-mecanica-cluster --region us-east-1' primeiro."
    exit 1
  fi

  log_info "Contexto atual: $(kubectl config current-context)"

  local metrics_ready
  metrics_ready=$(kubectl get apiservice v1beta1.metrics.k8s.io \
    -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "")
  if [ "$metrics_ready" != "True" ]; then
    log_error "metrics-server não está disponível. O HPA não tem como ler CPU/memória sem ele."
    exit 1
  fi
  log_success "metrics-server disponível"
}

deploy_load_generator() {
  log_info "Subindo load-generator com $REPLICAS réplicas contra http://${SERVICE_NAME}${TARGET_PATH}..."
  cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $LOAD_GEN_NAME
  labels:
    app: $LOAD_GEN_NAME
spec:
  replicas: $REPLICAS
  selector:
    matchLabels:
      app: $LOAD_GEN_NAME
  template:
    metadata:
      labels:
        app: $LOAD_GEN_NAME
    spec:
      containers:
        - name: $LOAD_GEN_NAME
          image: busybox
          command: ["/bin/sh", "-c", "while true; do wget -q -O- http://${SERVICE_NAME}${TARGET_PATH} > /dev/null; done"]
EOF
}

cleanup() {
  echo ""
  log_info "Removendo load-generator..."
  kubectl delete deployment "$LOAD_GEN_NAME" -n "$NAMESPACE" --ignore-not-found=true >/dev/null 2>&1 || true
  log_success "Load-generator removido. Scale-down do HPA leva ~5min (janela de estabilização padrão)."
}

print_status() {
  clear
  echo "=== HPA ($HPA_NAME) ==="
  kubectl get hpa "$HPA_NAME" -n "$NAMESPACE"
  echo
  echo "=== Pods da aplicação ($DEPLOYMENT_LABEL) ==="
  kubectl get pods -n "$NAMESPACE" -l "$DEPLOYMENT_LABEL" -o wide
  echo
  echo "=== CPU / Memória ==="
  kubectl top pods -n "$NAMESPACE" -l "$DEPLOYMENT_LABEL" 2>/dev/null || echo "Métricas ainda não disponíveis, aguarde..."
}

cmd_start() {
  check_prereqs
  trap cleanup EXIT INT TERM
  deploy_load_generator
  log_success "Load-generator no ar. Acompanhando o HPA a cada ${POLL_INTERVAL}s — Ctrl+C para parar e limpar."
  sleep 2
  while true; do
    print_status
    echo
    echo "Ctrl+C para encerrar o teste e remover o load-generator."
    sleep "$POLL_INTERVAL"
  done
}

cmd_stop() {
  check_prereqs
  cleanup
}

cmd_status() {
  check_prereqs
  print_status
}

case "$COMMAND" in
  start)
    cmd_start
    ;;
  stop)
    cmd_stop
    ;;
  status)
    cmd_status
    ;;
  *)
    cat <<EOF
Usage: $0 [COMMAND] [REPLICAS]

Testa o HorizontalPodAutoscaler (os-service-hpa) gerando carga real
contra o Service interno e acompanhando o scaling em tempo real.

Commands:
  start [replicas]  Sobe o load-generator (default: $DEFAULT_REPLICAS pods) e acompanha o HPA
                    até Ctrl+C, quando remove o load-generator automaticamente (default)
  stop              Remove o load-generator manualmente (caso o script tenha sido morto
                    abruptamente e o cleanup automático não tenha rodado)
  status            Mostra um snapshot único do HPA/pods/uso de recursos, sem gerar carga

Examples:
  $0 start        # gera carga com $DEFAULT_REPLICAS pods, observa o scaling, Ctrl+C encerra e limpa
  $0 start 10     # gera carga com 10 pods (mais concorrência)
  $0 stop         # remove o load-generator sem subir um novo teste
  $0 status       # snapshot rápido sem alterar nada

Pré-requisitos:
  kubectl configurado contra o cluster (aws eks update-kubeconfig --name oficina-mecanica-cluster --region us-east-1)
EOF
    exit 0
    ;;
esac

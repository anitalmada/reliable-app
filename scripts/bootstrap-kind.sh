#!/usr/bin/env bash
# Bootstrap a local Kind cluster and deploy Reliable App APIs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-reliable-app}"
KIND_CONFIG="${ROOT}/infra/k8s/kind-config.yaml"
KUSTOMIZE_DIR="${ROOT}/infra/k8s/base"
BIN_DIR="${HOME}/.local/bin"
export PATH="${BIN_DIR}:${PATH}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

ensure_kubectl() {
  if command -v kubectl >/dev/null 2>&1; then
    return
  fi
  log "kubectl not found; installing to ${BIN_DIR}"
  mkdir -p "${BIN_DIR}"
  local ver
  ver="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSL -o "${BIN_DIR}/kubectl" \
    "https://dl.k8s.io/release/${ver}/bin/linux/amd64/kubectl"
  chmod +x "${BIN_DIR}/kubectl"
}

ensure_kind() {
  if command -v kind >/dev/null 2>&1; then
    return
  fi
  log "kind not found; installing to ${BIN_DIR}"
  mkdir -p "${BIN_DIR}"
  local ver="v0.27.0"
  curl -fsSL -o "${BIN_DIR}/kind" \
    "https://kind.sigs.k8s.io/dl/${ver}/kind-linux-amd64"
  chmod +x "${BIN_DIR}/kind"
}

build_and_load() {
  local name="$1"
  local context="$2"
  local image="reliable-app/${name}:dev"
  log "Building ${image}"
  docker build -t "${image}" "${context}"
  log "Loading ${image} into Kind (${CLUSTER_NAME})"
  kind load docker-image "${image}" --name "${CLUSTER_NAME}"
}

wait_ready() {
  log "Waiting for deployments to become Ready"
  kubectl -n reliable-app rollout status deploy/postgres --timeout=120s
  kubectl -n reliable-app rollout status deploy/payments-mock --timeout=120s
  kubectl -n reliable-app rollout status deploy/catalog-api --timeout=120s
  kubectl -n reliable-app rollout status deploy/checkout-api --timeout=120s
  kubectl -n reliable-app rollout status deploy/prometheus --timeout=120s
}

print_usage() {
  cat <<'EOF'

Reliable App is up on Kind.

Local endpoints (host → NodePort via kind-config extraPortMappings):
  catalog-api    http://127.0.0.1:8081
  checkout-api   http://127.0.0.1:8082
  payments-mock  http://127.0.0.1:8083
  prometheus     http://127.0.0.1:9090

OpenAPI docs:
  http://127.0.0.1:8081/docs
  http://127.0.0.1:8082/docs
  http://127.0.0.1:8083/docs

SLOs / error budget:
  docs:  SLO_DEFINITION.md
  query: ./scripts/query-error-budget.sh
  gate:  ./scripts/check-error-budget.sh --min-remaining 0.20

Smoke test:
  ./scripts/smoke-test.sh

Tear down:
  kind delete cluster --name reliable-app

EOF
}

main() {
  need_cmd docker
  need_cmd curl
  docker info >/dev/null 2>&1 || die "Docker daemon is not running"

  ensure_kubectl
  ensure_kind

  if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
    log "Kind cluster '${CLUSTER_NAME}' already exists"
  else
    log "Creating Kind cluster '${CLUSTER_NAME}'"
    kind create cluster --config "${KIND_CONFIG}"
  fi

  build_and_load catalog-api "${ROOT}/app/catalog-api"
  build_and_load checkout-api "${ROOT}/app/checkout-api"
  build_and_load payments-mock "${ROOT}/app/payments-mock"

  log "Applying manifests (kustomize)"
  kubectl apply -k "${KUSTOMIZE_DIR}"

  wait_ready
  print_usage
}

main "$@"

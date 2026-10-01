#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/infra/terraform"
KUBE_CONTEXT="diploma-k8s"

if [[ "${DESTROY:-0}" != "1" ]]; then
    echo "ERROR: teardown destroys the Kubernetes cluster and persistent data." >&2
    echo "Run explicitly with DESTROY=1." >&2
    exit 1
fi

: "${TF_VAR_cloud_id:?Set TF_VAR_cloud_id}"
: "${TF_VAR_folder_id:?Set TF_VAR_folder_id}"
: "${TF_VAR_admin_cidr:?Set TF_VAR_admin_cidr}"

CURRENT_CONTEXT="$(kubectl config current-context)"
if [[ "$CURRENT_CONTEXT" != "$KUBE_CONTEXT" ]]; then
    echo "ERROR: expected context '$KUBE_CONTEXT', got '$CURRENT_CONTEXT'." >&2
    exit 1
fi

echo "==> Stopping Telegram alert bridge"
sudo systemctl disable --now telegram-alert-bridge.timer 2>/dev/null || true

echo "==> Removing Kubernetes workloads and external LoadBalancer"

helm uninstall nginx-ingress -n nginx-ingress --ignore-not-found || true
kubectl --context "$KUBE_CONTEXT" delete namespace diploma monitoring argocd \
    --ignore-not-found --wait=true --timeout=10m || true

echo "==> Destroying Terraform infrastructure"
terraform -chdir="$TF_DIR" destroy

echo "Teardown completed."

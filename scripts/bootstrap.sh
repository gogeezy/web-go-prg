#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/infra/terraform"
KUBE_CONTEXT="diploma-k8s"
CLUSTER_NAME="diploma-k8s"

NGINX_CHART_VERSION="2.7.3"
MONITORING_CHART_VERSION="90.1.0"
ARGOCD_VERSION="v3.5.3"

: "${TF_VAR_cloud_id:?Set TF_VAR_cloud_id}"
: "${TF_VAR_folder_id:?Set TF_VAR_folder_id}"
: "${TF_VAR_admin_cidr:?Set TF_VAR_admin_cidr}"
: "${TELEGRAM_BOT_TOKEN:?Set TELEGRAM_BOT_TOKEN}"
: "${TELEGRAM_CHAT_ID:?Set TELEGRAM_CHAT_ID}"

for cmd in terraform yc kubectl helm curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: required command '$cmd' is not installed." >&2
        exit 1
    fi
done

if [[ -z "${YC_TOKEN:-}" ]]; then
    YC_TOKEN="$(yc iam create-token)"
    export YC_TOKEN
fi

echo "Bootstrap prerequisites: OK"
echo "Cluster: $CLUSTER_NAME"
echo "Argo CD: $ARGOCD_VERSION"
echo "NGINX chart: $NGINX_CHART_VERSION"
echo "Monitoring chart: $MONITORING_CHART_VERSION"

echo "==> Provisioning Yandex Cloud infrastructure"
terraform -chdir="$TF_DIR" init
terraform -chdir="$TF_DIR" validate
terraform -chdir="$TF_DIR" apply -auto-approve

echo "==> Configuring Kubernetes access"
yc managed-kubernetes cluster get-credentials "$CLUSTER_NAME" \
    --external \
    --context-name "$KUBE_CONTEXT" \
    --force

CURRENT_CONTEXT="$(kubectl config current-context)"
if [[ "$CURRENT_CONTEXT" != "$KUBE_CONTEXT" ]]; then
    echo "ERROR: expected context '$KUBE_CONTEXT', got '$CURRENT_CONTEXT'." >&2
    exit 1
fi

kubectl --context "$KUBE_CONTEXT" wait \
    --for=condition=Ready node \
    --all \
    --timeout=10m

echo "Kubernetes cluster: READY"

echo "==> Installing NGINX Ingress"
helm upgrade --install nginx-ingress \
    oci://ghcr.io/nginx/charts/nginx-ingress \
    --namespace nginx-ingress \
    --create-namespace \
    --version "$NGINX_CHART_VERSION" \
    --wait \
    --timeout 10m

echo "==> Waiting for NGINX public IP"
for _ in {1..60}; do
    INGRESS_IP="$(kubectl --context "$KUBE_CONTEXT" \
        -n nginx-ingress \
        get svc nginx-ingress-controller \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"

    if [[ -n "$INGRESS_IP" ]]; then
        break
    fi

    sleep 10
done

if [[ -z "${INGRESS_IP:-}" ]]; then
    echo "ERROR: NGINX LoadBalancer did not receive a public IP." >&2
    exit 1
fi

APP_HOST="${INGRESS_IP}.nip.io"
echo "NGINX public IP: $INGRESS_IP"
echo "Application host: $APP_HOST"

echo "==> Installing Argo CD"
kubectl --context "$KUBE_CONTEXT" create namespace argocd \
    --dry-run=client -o yaml | \
    kubectl --context "$KUBE_CONTEXT" apply -f -

kubectl --context "$KUBE_CONTEXT" apply -n argocd \
    -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

kubectl --context "$KUBE_CONTEXT" -n argocd rollout status \
    deployment/argocd-server \
    --timeout=10m

echo "==> Creating database Secret"
EXPECTED_CONTEXT="$KUBE_CONTEXT" \
ALLOW_NEW_DATABASE=1 \
bash "$ROOT_DIR/scripts/create-db-secret.sh"

echo "Argo CD and database Secret: READY"

echo "==> Installing monitoring stack"
helm repo add prometheus-community \
    https://prometheus-community.github.io/helm-charts \
    --force-update

helm repo update

helm upgrade --install monitoring \
    prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    --version "$MONITORING_CHART_VERSION" \
    --values "$ROOT_DIR/deploy/monitoring/values.yaml" \
    --wait \
    --timeout 15m

echo "==> Installing Grafana application dashboard"
kubectl --context "$KUBE_CONTEXT" apply \
    -f "$ROOT_DIR/deploy/monitoring/app-dashboard.yaml"

echo "Monitoring: READY"

echo "==> Configuring Argo CD application"
kubectl --context "$KUBE_CONTEXT" apply \
    -f "$ROOT_DIR/deploy/argocd/application.yaml"

kubectl --context "$KUBE_CONTEXT" -n argocd patch application diploma \
    --type merge \
    -p "{\"spec\":{\"source\":{\"helm\":{\"parameters\":[{\"name\":\"ingress.hosts[0].host\",\"value\":\"${APP_HOST}\"}]}}}}"

echo "==> Waiting for application deployment"
for _ in {1..60}; do
    if kubectl --context "$KUBE_CONTEXT" -n diploma get deployment diploma-web-go-prg \
        >/dev/null 2>&1; then
        break
    fi
    sleep 5
done

if ! kubectl --context "$KUBE_CONTEXT" -n diploma get deployment diploma-web-go-prg \
    >/dev/null 2>&1; then
    echo "ERROR: application Deployment was not created by Argo CD." >&2
    exit 1
fi

kubectl --context "$KUBE_CONTEXT" -n diploma rollout status \
    deployment/diploma-web-go-prg \
    --timeout=10m

echo "Application: READY at http://${APP_HOST}"


echo "==> Configuring Telegram alert bridge"

kubectl --context "$KUBE_CONTEXT" -n monitoring create secret generic monitoring-telegram \
    --from-literal=bot-token="$TELEGRAM_BOT_TOKEN" \
    --from-literal=chat-id="$TELEGRAM_CHAT_ID" \
    --dry-run=client -o yaml | \
    kubectl --context "$KUBE_CONTEXT" apply -f -

CURRENT_USER="$(id -un)"
CURRENT_HOME="$HOME"

sed \
    -e "s|^User=.*|User=${CURRENT_USER}|" \
    -e "s|^Environment=HOME=.*|Environment=HOME=${CURRENT_HOME}|" \
    -e "s|^WorkingDirectory=.*|WorkingDirectory=${ROOT_DIR}|" \
    -e "s|^ExecStart=.*|ExecStart=/usr/bin/python3 ${ROOT_DIR}/scripts/telegram-alert-bridge.py|" \
    "$ROOT_DIR/deploy/systemd/telegram-alert-bridge.service" | \
    sudo tee /etc/systemd/system/telegram-alert-bridge.service >/dev/null

sudo cp "$ROOT_DIR/deploy/systemd/telegram-alert-bridge.timer" \
    /etc/systemd/system/telegram-alert-bridge.timer

sudo systemctl daemon-reload
sudo systemctl enable --now telegram-alert-bridge.timer

echo "==> Verifying public application"
curl --fail --silent --show-error \
    --retry 12 \
    --retry-delay 5 \
    "http://${APP_HOST}/healthz" >/dev/null

echo
echo "Bootstrap completed successfully."
echo "Application: http://${APP_HOST}"
echo "Kubernetes context: ${KUBE_CONTEXT}"

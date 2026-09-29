#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=diploma
SECRET_NAME=web-go-prg-db

# Защита от случайного запуска в другом кластере.
: "${EXPECTED_CONTEXT:?Specify the expected Kubernetes context}"

CURRENT_CONTEXT=$(kubectl config current-context)

if [[ "$CURRENT_CONTEXT" != "$EXPECTED_CONTEXT" ]]; then
    echo "Error: unexpected Kubernetes context."
    exit 1
fi

# Создаём namespace, только если его ещё нет.
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    kubectl create namespace "$NAMESPACE"
fi

# Не изменяем пароль существующей базы данных.
if kubectl -n "$NAMESPACE" get secret "$SECRET_NAME" \
    >/dev/null 2>&1; then
    echo "Database Secret already exists. No changes made."
    exit 0
fi

# Генерируем пароль и адрес PostgreSQL.
PASSWORD=$(openssl rand -hex 24)

DATABASE_URL="postgres://postgres:${PASSWORD}@diploma-postgresql:5432/web_go_prg?sslmode=disable"

# Передаём Secret в Kubernetes через стандартный ввод.
# Пароль не записывается в файл на диске.
{
    printf 'apiVersion: v1\n'
    printf 'kind: Secret\n'
    printf 'metadata:\n'
    printf '  name: %s\n' "$SECRET_NAME"
    printf '  namespace: %s\n' "$NAMESPACE"
    printf 'type: Opaque\n'
    printf 'data:\n'

    printf '  password: %s\n' \
        "$(printf '%s' "$PASSWORD" | base64 | tr -d '\n')"

    printf '  database-url: %s\n' \
        "$(printf '%s' "$DATABASE_URL" | base64 | tr -d '\n')"
} | kubectl create -f -

unset PASSWORD DATABASE_URL

echo "Database Secret created successfully."

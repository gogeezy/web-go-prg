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

    if [[ ! -s "$HOME/.config/web-go-prg/db-password" ]]; then
        echo "ERROR: Secret exists, but local password backup is missing." >&2
        exit 1
    fi

    echo "Database Secret already exists. No changes made."
    exit 0
fi

# Генерируем пароль и адрес PostgreSQL.
PASSWORD_FILE="$HOME/.config/web-go-prg/db-password"

# Только владелец может читать файлы с паролями.
umask 077
mkdir -p "$(dirname "$PASSWORD_FILE")"
chmod 700 "$(dirname "$PASSWORD_FILE")"

if [[ -f "$PASSWORD_FILE" ]]; then
    PASSWORD=$(<"$PASSWORD_FILE")
    if [[ -z "$PASSWORD" ]]; then
        echo "Error: password file is empty." >&2
        exit 1
    fi
else
    # Не создаём новый пароль для существующей базы.
    PVC_NAME=postgres-data-diploma-postgresql-0

    EXISTING_PVC=$(kubectl -n "$NAMESPACE" get pvc "$PVC_NAME" \
        --ignore-not-found -o name)

    if [[ -n "$EXISTING_PVC" ]]; then
        echo "ERROR: PostgreSQL PVC exists, but password file is missing." >&2
        echo "Restore the original password from backup." >&2
        exit 1
    fi

    # Новый пароль разрешён только при первом развёртывании.
    if [[ "${ALLOW_NEW_DATABASE:-0}" != "1" ]]; then
        echo "ERROR: Password file is missing." >&2
        echo "Restore the password from backup." >&2
        echo "For a verified new database, set ALLOW_NEW_DATABASE=1." >&2
        exit 1
    fi

    PASSWORD=$(openssl rand -hex 24)
    (set -C; printf '%s\n' "$PASSWORD" > "$PASSWORD_FILE")
fi
chmod 600 "$PASSWORD_FILE"

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

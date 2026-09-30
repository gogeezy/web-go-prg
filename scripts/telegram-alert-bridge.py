#!/usr/bin/env python3

import base64
import hashlib
import json
import os
import subprocess
import urllib.parse
import urllib.request
from pathlib import Path

CONTEXT = os.getenv("KUBE_CONTEXT", "diploma-k8s")
NAMESPACE = "monitoring"
SECRET = "monitoring-telegram"
STATE_FILE = Path.home() / ".local/state/web-go-prg/telegram-alerts.json"

ALERTS_PATH = (
    "/api/v1/namespaces/monitoring/services/"
    "http:monitoring-kube-prometheus-alertmanager:9093/"
    "proxy/api/v2/alerts"
)


def kubectl_json(*args):
    output = subprocess.check_output(
        ["kubectl", "--context", CONTEXT, *args],
        text=True,
    )
    return json.loads(output)


def get_credentials():
    secret = kubectl_json(
        "-n", NAMESPACE,
        "get", "secret", SECRET,
        "-o", "json",
    )
    data = secret["data"]
    token = base64.b64decode(data["bot-token"]).decode().strip()
    chat_id = base64.b64decode(data["chat-id"]).decode().strip()
    return token, chat_id


def get_alerts():
    return kubectl_json("get", "--raw", ALERTS_PATH)


def fingerprint(alert):
    value = alert.get("fingerprint")
    if value:
        return value
    raw = json.dumps(alert.get("labels", {}), sort_keys=True).encode()
    return hashlib.sha256(raw).hexdigest()


def message(prefix, alert):
    labels = alert.get("labels", {})
    annotations = alert.get("annotations", {})

    name = labels.get("alertname", "unknown")
    severity = labels.get("severity", "unknown")
    namespace = labels.get("namespace", "-")
    summary = annotations.get("summary", "")
    description = annotations.get("description", "")

    lines = [
        f"{prefix}: {name}",
        f"Severity: {severity}",
        f"Namespace: {namespace}",
    ]
    if summary:
        lines.append(f"Summary: {summary}")
    if description:
        lines.append(f"Description: {description}")

    return "\n".join(lines)


def send_telegram(token, chat_id, text):
    payload = urllib.parse.urlencode({
        "chat_id": chat_id,
        "text": text,
    }).encode()

    request = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data=payload,
        method="POST",
    )

    with urllib.request.urlopen(request, timeout=15) as response:
        result = json.load(response)

    if not result.get("ok"):
        raise RuntimeError("Telegram did not confirm message")


def load_state():
    try:
        return json.loads(STATE_FILE.read_text())
    except FileNotFoundError:
        return {}


def save_state(state):
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    temporary = STATE_FILE.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, indent=2))
    temporary.replace(STATE_FILE)


def main():
    token, chat_id = get_credentials()
    alerts = get_alerts()
    previous = load_state()

    current = {}
    for alert in alerts:
        status = alert.get("status", {})
        if status.get("state") != "active":
            continue
        if status.get("silencedBy") or status.get("inhibitedBy"):
            continue
        current[fingerprint(alert)] = alert

    next_state = {}
    sent = 0
    resolved = 0

    for key, alert in current.items():
        if key not in previous:
            send_telegram(token, chat_id, message("FIRING", alert))
            sent += 1
        next_state[key] = alert

    for key, alert in previous.items():
        if key not in current:
            send_telegram(token, chat_id, message("RESOLVED", alert))
            resolved += 1

    save_state(next_state)
    print(f"active={len(current)} sent={sent} resolved={resolved}")


if __name__ == "__main__":
    main()

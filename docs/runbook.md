
# Runbook: web-go-prg

## PostgreSQL: хранение и восстановление пароля

Пароль PostgreSQL не хранится в Git.

Скрипт `scripts/create-db-secret.sh` сохраняет его локально:
`~/.config/web-go-prg/db-password`

Права доступа к файлу: 600.
Права доступа к каталогу: 700.

### Первое развёртывание

1. Проверить подключение к нужному Kubernetes-кластеру.
2. Убедиться, что создаётся новая база данных.
3. Указать EXPECTED_CONTEXT (проверенный контекст целевого Kubernetes-
   кластера), установить ALLOW_NEW_DATABASE=1 и запустить скрипт.
4. Сохранить пароль в защищённом менеджере паролей
   вне Ubuntu Server.
5. Проверить наличие резервной копии до дальнейшей работы.

### Восстановление

Если локальный файл утрачен:

1. Не генерировать новый пароль.
2. Восстановить исходный пароль из защищённой
   резервной копии.
3. Создать файл по прежнему пути с правами 600.
4. Проверить Kubernetes-контекст.
5. Проверить соответствие восстановленного пароля
   существующей базе данных.
6. При необходимости повторно создать Kubernetes Secret.

Если резервная копия отсутствует, остановить
развёртывание и разобраться с состоянием существующей
базы и Kubernetes Secret.

Никогда не отправлять пароли в GitHub, логи CI
или чат.

---

## Проверка состояния production

Перед диагностикой проверить Kubernetes context:

```bash
kubectl config current-context
```

Ожидаемый context:

`diploma-k8s`

Проверить узлы и основные namespace:

```bash
kubectl get nodes
kubectl get pods -n diploma
kubectl get pods -n argocd
kubectl get pods -n monitoring
```

Узел должен находиться в состоянии `Ready`, а рабочие Pod — в состоянии `Running` или `Completed`.

## Проверка приложения

Проверить Deployment и используемый Docker image:

```bash
kubectl -n diploma get deployment diploma-web-go-prg
kubectl -n diploma get deployment diploma-web-go-prg \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Проверить Ingress:

```bash
kubectl -n diploma get ingress
```

После получения hostname проверить health endpoint:

```bash
curl http://<EXTERNAL-IP>.nip.io/healthz
```

Ожидается HTTP 200.

## Проверка PostgreSQL и PersistentVolume

Проверить PostgreSQL Pod и PVC:

```bash
kubectl -n diploma get pods
kubectl -n diploma get pvc
```

PVC PostgreSQL должен находиться в состоянии `Bound`.

При пересоздании PostgreSQL Pod данные должны оставаться на PersistentVolume. Удаление PVC является отдельной разрушительной операцией и может привести к потере данных.

## Проверка Argo CD

Проверить состояние GitOps Application:

```bash
kubectl -n argocd get applications
```

Для application `diploma` ожидаются:

- Sync Status: `Synced`;
- Health Status: `Healthy`.

Если приложение не синхронизировано, получить подробное состояние:

```bash
kubectl -n argocd describe application diploma
```

Production Deployment не следует вручную изменять через `kubectl edit` или `kubectl set image`. Изменения production должны проходить через Git и Argo CD.

## Rollback

Для rollback определить ранее работавший immutable image tag вида:

`ghcr.io/gogeezy/web-go-prg:sha-<commit>`

Указать этот tag в `deploy/helm/web-go-prg/values-prod.yaml`, создать Git-коммит и отправить его в `main`.

После этого проверить:

```bash
kubectl -n argocd get applications
kubectl -n diploma rollout status deployment/diploma-web-go-prg
```

Затем убедиться, что Deployment использует требуемый image:

```bash
kubectl -n diploma get deployment diploma-web-go-prg \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

После проверки rollback рабочую версию можно восстановить таким же GitOps-изменением.

## Мониторинг

Проверить компоненты monitoring stack:

```bash
kubectl -n monitoring get pods
```

Проверить ServiceMonitor и PrometheusRule приложения:

```bash
kubectl -n diploma get servicemonitor
kubectl -n diploma get prometheusrule
```

Grafana dashboard `Web Go App` содержит состояние приложения, количество HTTP-запросов, request rate по endpoint и HTTP 4xx/5xx rate.

## Алерты

Настроены два application alert:

`ApplicationDown` — приложение недоступно для Prometheus.

`HTTPErrorBurst` — за короткий интервал возникло повышенное количество HTTP 4xx/5xx ответов.

При получении alert сначала проверить:

```bash
kubectl -n diploma get pods
kubectl -n diploma get deployment diploma-web-go-prg
kubectl -n argocd get applications
```

Для `ApplicationDown` дополнительно проверить health endpoint и состояние ServiceMonitor.

Для `HTTPErrorBurst` проверить состояние приложения и HTTP-запросы, вызвавшие ошибки.

## Telegram alert bridge

Telegram bridge работает на управляющем Ubuntu-сервере через systemd timer.

Проверить timer:

```bash
systemctl status telegram-alert-bridge.timer
```

Проверить последний запуск:

```bash
systemctl status telegram-alert-bridge.service
```

Посмотреть журнал:

```bash
journalctl -u telegram-alert-bridge.service --no-pager -n 50
```

Bot token и chat ID хранятся в Kubernetes Secret `monitoring-telegram` и не должны выводиться в логи или сохраняться в Git.

## Развёртывание

Для полного автоматизированного развёртывания используется:

```bash
./scripts/bootstrap.sh
```

Перед запуском необходимо настроить доступ к Yandex Cloud и требуемые переменные окружения.

Bootstrap создаёт Terraform-инфраструктуру и устанавливает необходимые компоненты Kubernetes.

## Полный teardown

Полное удаление стенда выполняется только осознанно:

```bash
DESTROY=1 ./scripts/teardown.sh
```

Teardown является разрушительной операцией. При удалении namespace и инфраструктуры данные PostgreSQL могут быть удалены вместе с PersistentVolume.

Перед teardown убедиться, что важные данные и необходимые секреты сохранены вне кластера.

# web-go-prg

Базовое веб-приложение на Go с приветственной страницей и калькулятором. История операций суммы хранится в **PostgreSQL**.

## База данных

**Кто что создаёт**

1. **База данных** с именем `web_go_prg` появляется при **первом запуске** контейнера PostgreSQL из Docker Compose: образ выполняет инициализацию и создаёт БД из переменной окружения `POSTGRES_DB` (см. [docker-compose.yml](docker-compose.yml)). Отдельной команды `CREATE DATABASE` в приложении нет — приложение подключается к уже существующей БД из строки подключения (в пути DSN указано имя базы: `.../web_go_prg?...`).

2. **Таблицы** (например `operation_history`) создаёт **приложение** при старте: в коде вызывается `EnsureSchema` ([internal/history/history.go](internal/history/history.go)), эквивалентно SQL из [migrations/001_init.sql](migrations/001_init.sql).

Проверить, что БД есть, можно так:

```bash
docker compose exec db psql -U postgres -d web_go_prg -c '\dt'
```

После работы приложения в списке должна быть таблица `operation_history`.

### Docker Compose (PostgreSQL)

В репозитории есть [docker-compose.yml](docker-compose.yml). Содержимое:

```yaml
services:
  db:
    image: postgres:16-alpine
    ...
  web:
    build: .
    ports: ["8080:8080"]
    environment:
      DATABASE_URL: postgres://postgres:postgres@db:5432/web_go_prg?sslmode=disable
    depends_on:
      db: { condition: service_healthy }
```

Полный файл — в [docker-compose.yml](docker-compose.yml): сервис **web** собирается из [Dockerfile](Dockerfile), подключается к **db** по имени хоста `db`.

Запуск в фоне из корня проекта (сборка образа приложения и старт Postgres):

```bash
docker compose up -d --build
```

Остановка и удаление контейнеров (данные в томе `pgdata` сохраняются):

```bash
docker compose down
```

Приложение в compose: **http://localhost:8080/**. С хоста к Postgres по-прежнему:

`postgres://postgres:postgres@localhost:5432/web_go_prg?sslmode=disable`

Переопределить можно переменной окружения:

```bash
export DATABASE_URL='postgres://user:pass@host:5432/dbname?sslmode=disable'
```

Схема также описана в [migrations/001_init.sql](migrations/001_init.sql); при старте приложение создаёт таблицу `operation_history`, если её ещё нет.

## Запуск

Нужен запущенный PostgreSQL (см. выше). Из корня проекта:

```bash
go run .
```

Или сборка и запуск бинарника:

```bash
go build -o web-go-prg
./web-go-prg
```

По умолчанию сервер слушает порт **8080**. Порт можно задать через переменную окружения:

```bash
PORT=3000 go run .
```

Приветственная страница доступна по адресу: **http://localhost:8080/**

## Docker (образ приложения)

Сборка описана в [Dockerfile](Dockerfile): многостадийная сборка Go, в финальном образе — `distroless/static-debian12:nonroot`, бинарник и каталог `templates/`. Контекст сборки уменьшает [.dockerignore](.dockerignore).

```bash
docker build -t web-go-prg .
```

Запуск контейнера (PostgreSQL должен быть доступен по сети; при `docker compose up -d db` на хосте порт 5432 проброшен):

```bash
docker run --rm -p 8080:8080 --add-host=host.docker.internal:host-gateway \
  -e DATABASE_URL='postgres://postgres:postgres@host.docker.internal:5432/web_go_prg?sslmode=disable' \
  web-go-prg
```

Флаг `--add-host=host.docker.internal:host-gateway` нужен на Linux, чтобы из контейнера достучаться до Postgres на хосте. В Docker Desktop для Mac/Windows `host.docker.internal` обычно уже есть.

## Тесты

Запуск всех тестов из корня проекта:

```bash
go test ./...
```

Только тесты пакета калькулятора:

```bash
go test ./internal/calculator/...
```

---

## Production-инфраструктура

Production-окружение развёртывается в Yandex Cloud на базе Managed Service for Kubernetes.

Инфраструктура описана Terraform в каталоге [`infra/terraform`](infra/terraform). Terraform создаёт VPC, подсеть, security group, service account, Managed Kubernetes cluster и node group.

Kubernetes-манифесты приложения упакованы в Helm chart [`deploy/helm/web-go-prg`](deploy/helm/web-go-prg).

Подробная схема компонентов и потоков находится в [`docs/architecture.md`](docs/architecture.md).

## Публичный доступ

Приложение публикуется через NGINX Ingress Controller и Yandex Cloud Network Load Balancer.

После развёртывания внешний адрес имеет вид:

`http://<EXTERNAL-IP>.nip.io`

Проверка состояния приложения:

```bash
curl http://<EXTERNAL-IP>.nip.io/healthz
```

Приложение также предоставляет:

- `/readyz` — readiness probe;
- `/metrics` — Prometheus metrics.

## CI/CD и GitOps

GitHub Actions выполняет CI для изменений в репозитории: запускает тесты, проверяет Helm chart и собирает Docker image.

Образы публикуются в GitHub Container Registry (GHCR) с immutable-тегом, содержащим SHA Git-коммита.

Для ветки `main` workflow автоматически обновляет production image tag в `deploy/helm/web-go-prg/values-prod.yaml`.

Argo CD отслеживает ветку `main` и автоматически синхронизирует состояние Kubernetes с Git.

Production-поток:

`Git push -> GitHub Actions -> GHCR -> GitOps commit -> Argo CD -> Kubernetes`

Это позволяет выполнять deployment и rollback через историю Git без ручного изменения Deployment в Kubernetes.

## Хранение данных

PostgreSQL развёрнут в Kubernetes вместе с приложением и использует PersistentVolumeClaim.

Данные сохраняются при удалении и повторном создании Pod PostgreSQL. Это позволяет отделить жизненный цикл Pod от жизненного цикла данных.

Секрет подключения к базе данных хранится в Kubernetes Secret `web-go-prg-db` и не сохраняется в Git.

## Мониторинг и алерты

Для мониторинга используется `kube-prometheus-stack`:

- Prometheus собирает метрики приложения через ServiceMonitor;
- Grafana содержит dashboard `Web Go App`;
- PrometheusRule определяет алерты `ApplicationDown` и `HTTPErrorBurst`;
- Alertmanager обрабатывает срабатывания алертов.

Telegram-уведомления доставляются через `scripts/telegram-alert-bridge.py`, запущенный systemd timer на управляющем Ubuntu-сервере. Bridge получает активные alerts из Alertmanager и отправляет состояния FIRING/RESOLVED в Telegram.

## Автоматическое развёртывание

Для воспроизводимого развёртывания используется:

```bash
./scripts/bootstrap.sh
```

Перед запуском должны быть настроены `yc`, `kubectl`, `helm`, `terraform` и доступ к Yandex Cloud.

Скрипту передаются необходимые параметры Terraform и Telegram через переменные окружения. Секреты не должны сохраняться в Git.

Bootstrap выполняет создание инфраструктуры, настройку Kubernetes context, установку NGINX Ingress, Argo CD и monitoring stack, создание необходимых Kubernetes Secrets и запуск Telegram alert bridge.

## Безопасное удаление стенда

Удаление инфраструктуры защищено дополнительным подтверждением через переменную `DESTROY`.

```bash
DESTROY=1 ./scripts/teardown.sh
```

Скрипт удаляет Kubernetes workloads и LoadBalancer, после чего запускает `terraform destroy`.

Команда является разрушительной: PersistentVolume и данные PostgreSQL при полном teardown могут быть удалены.

## Rollback

Rollback production выполняется через Git: в `values-prod.yaml` возвращается ранее работавший immutable image tag `sha-<commit>`, изменение коммитится в `main`, после чего Argo CD синхронизирует предыдущую версию приложения.

Проверка состояния Argo CD:

```bash
kubectl -n argocd get applications
```

Проверка фактически запущенного image:

```bash
kubectl -n diploma get deployment diploma-web-go-prg \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

## Основные каталоги

- `infra/terraform/` — инфраструктура Yandex Cloud;
- `deploy/helm/web-go-prg/` — Helm chart приложения;
- `deploy/argocd/` — конфигурация Argo CD;
- `deploy/monitoring/` — monitoring values и Grafana dashboard;
- `deploy/systemd/` — systemd units Telegram bridge;
- `scripts/` — bootstrap, teardown и эксплуатационные скрипты;
- `docs/` — архитектура и runbook.

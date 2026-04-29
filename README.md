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

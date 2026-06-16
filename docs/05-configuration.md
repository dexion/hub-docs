# 05. Конфигурация (Environment Variables)

Полный справочник переменных окружения Hub. Все варианты задаются через env vars в `.env` (для compose), Helm `values.yaml` (для K8s), или `hub.env` (для bare-metal).

## Соглашения

- **Required** — Hub не запустится / упадёт без неё
- **Recommended** — дефолт работает, но в production стоит задать явно
- **Optional** — фича включается только при наличии переменной

> Дефолтные значения JWT/admin password из `.env.example` **небезопасны для production**. Всегда генерируйте свои случайные значения.

## Application

| Переменная          | Тип                                   | Default                     | Описание                                                                                  |
| ------------------- | ------------------------------------- | --------------------------- | ----------------------------------------------------------------------------------------- |
| `APP_ENV`           | `development` / `production` / `test` | `development`               | Влияет на логирование, валидации (например, `production` запрещает HTTP-URL для Keycloak) |
| `SERVER_PORT`       | int                                   | `8082`                      | Порт backend API                                                                          |
| `FRONTEND_URL`      | URL                                   | `http://localhost:3000`     | Используется для редиректов                                                               |
| `FRONTEND_BASE_URL` | URL                                   | `http://localhost:3000`     | Префикс для ссылок в уведомлениях (Telegram/Mattermost/Jira)                              |
| `REACT_APP_API_URL` | URL                                   | `http://localhost:8082`     | Build-time для frontend; куда фронт шлёт API-запросы                                      |
| `ALLOWED_ORIGINS`   | CSV URLs                              | `http://localhost:3000,...` | CORS-allowlist                                                                            |

## Database

| Переменная    | Тип      | Default                                          | Описание        |
| ------------- | -------- | ------------------------------------------------ | --------------- |
| `DB_HOST`     | hostname | `sshub-postgres` (compose)                       | PostgreSQL host |
| `DB_PORT`     | int      | `5432`                                           | PostgreSQL port |
| `DB_NAME`     | string   | `securityhub`                                    | Имя БД          |
| `DB_USER`     | string   | `securityhub`                                    | DB user         |
| `DB_PASSWORD` | secret   | `securityhub123` (compose default — небезопасно) | DB password     |

> **Required for production**: задайте `DB_PASSWORD`. Дефолт — публичная заглушка.

## Authentication (JWT + Local)

| Переменная                 | Тип             | Default                        | Описание                                                                                    |
| -------------------------- | --------------- | ------------------------------ | ------------------------------------------------------------------------------------------- |
| `JWT_SECRET`               | secret          | `change-this-secret-key`       | **Required for production**. Подпись HS256 для внутренних JWT. Минимум 32 случайных символа |
| `ACCESS_TOKEN_TTL_MINUTES` | int             | `15`                           | TTL access JWT                                                                              |
| `REFRESH_TOKEN_TTL_DAYS`   | int             | `7`                            | TTL refresh token                                                                           |
| `AUTH_MODE`                | `LOCAL` / `SSO` | —                              | `LOCAL` — логин по паролю; `SSO` — через Keycloak                                           |
| `LOCAL_ADMIN_PASSWORD`     | secret          | `Admin1234!` (compose default) | Пароль для `admin@localhost.local` при `AUTH_MODE=LOCAL`. **Required for production**       |

## Keycloak / SSO

| Переменная               | Тип    | Default         | Описание                                                                        |
| ------------------------ | ------ | --------------- | ------------------------------------------------------------------------------- |
| `KEYCLOAK_URL`           | URL    | —               | Внутренний URL Keycloak (для backend → token exchange, JWKS)                    |
| `KEYCLOAK_PUBLIC_URL`    | URL    | —               | Публичный URL Keycloak (для редиректа браузера). В production обязан быть HTTPS |
| `KEYCLOAK_REALM`         | string | `securityhub`   | Realm имя                                                                       |
| `KEYCLOAK_CLIENT_ID`     | string | `security-hub`  | OIDC client ID                                                                  |
| `KEYCLOAK_CLIENT_SECRET` | secret | —               | Client secret. **Required for SSO**                                             |
| `KEYCLOAK_JWKS_URL`      | URL    | auto-discovered | Override JWKS endpoint (для split-network)                                      |
| `KEYCLOAK_TOKEN_URL`     | URL    | auto-discovered | Override token endpoint                                                         |

### Transparent SSO (внешний JWT)

| Переменная                         | Тип         | Default        | Описание                                                               |
| ---------------------------------- | ----------- | -------------- | ---------------------------------------------------------------------- |
| `FEATURE_SECURITY_HUB_INTEGRATION` | bool        | `false`        | Мастер-переключатель прозрачной аутентификации                         |
| `KC_JWKS_URL`                      | URL         | —              | JWKS внешнего Keycloak                                                 |
| `KC_ISSUER`                        | URL         | —              | Ожидаемое значение `iss` в JWT                                         |
| `KC_AUDIENCES`                     | CSV strings | `security-hub` | Разрешённые значения `aud`. **Не использовать `account` в production** |
| `KC_AUTO_PROVISION`                | bool        | `true`         | Создавать ли пользователя автоматически при первом валидном JWT        |
| `ATOM_IDP_BASE_URL`                | URL         | —              | URL atom-idp (добавляется в CORS allowlist)                            |

Подробнее: [`06-integration-keycloak.md`](06-integration-keycloak.md).

## Jira

| Переменная                           | Тип      | Default | Описание                                                                                                                                  |
| ------------------------------------ | -------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `FALLBACK_JIRA_URL`                  | URL      | —       | Используется в шаблонах, когда у проекта нет `jira_config.base_url`                                                                       |
| `JIRA_ALLOW_HTTP`                    | bool     | `false` | Разрешить ли HTTP (без TLS) для Jira. **Только dev**                                                                                      |
| `JIRA_ALLOW_LOCAL_DIAL`              | bool     | `false` | Разрешить ли коннект к RFC1918. **Только для self-hosted Jira во внутренней сети**                                                        |
| `JIRA_BASE_URL_ALLOWLIST`            | CSV URLs | —       | Whitelist хостов для Jira (опционально, доп. защита от SSRF)                                                                              |
| `FEATURE_JIRA_REVERSE_SYNC`          | bool     | `false` | Включает периодическую синхронизацию статусов Jira → Hub                                                                                  |
| `JIRA_REVERSE_SYNC_INTERVAL_MINUTES` | int      | `60`    | Интервал worker'а                                                                                                                         |
| `JIRA_REVERSE_SYNC_BATCH_SIZE`       | int      | `500`   | Сколько findings проверяется за один tick                                                                                                 |
| `JIRA_SYNC_WORKERS`                  | int      | `4`     | Параллелизм очереди auto-create                                                                                                           |
| `FEATURE_AUTO_VERIFY_FIXES`          | bool     | `false` | Включает auto-close findings, отсутствующих в новом отчёте (требует ещё `project.auto_verify_fixes_enabled` + `verify_fixes=true` в form) |

Подробнее: [`07-integration-jira.md`](07-integration-jira.md).

## Notifications

| Переменная                        | Тип    | Default | Описание                                           |
| --------------------------------- | ------ | ------- | -------------------------------------------------- |
| `DISPATCHER_WORKERS`              | int    | `10`    | Воркеры, распределяющие события по каналам         |
| `TELEGRAM_NOTIFICATION_WORKERS`   | int    | `5`     | Параллелизм отправки в Telegram                    |
| `MATTERMOST_NOTIFICATION_WORKERS` | int    | `10`    | Параллелизм отправки в Mattermost                  |
| `NOTIFICATIONS_DRY_RUN`           | bool   | `false` | Тестовый режим — логировать, не отправлять         |

## LLM (AI-триаж)

| Переменная                     | Тип    | Default       | Описание                                         |
| ------------------------------ | ------ | ------------- | ------------------------------------------------ |
| `LLM_BASE_URL`                 | URL    | —             | Базовый URL LLM-API (OpenAI-compatible)          |
| `LLM_API_KEY`                  | secret | —             | API-ключ                                         |
| `LLM_MODEL`                    | string | `glm-4-flash` | Модель                                           |
| `LLM_DRY_RUN`                  | bool   | `false`       | Без отправки реальных запросов                   |
| `LLM_FALSE_POSITIVE_THRESHOLD` | float  | `0.85`        | Минимальная уверенность для пометки FP           |
| `LLM_WORKERS`                  | int    | `3`           | Воркеры. **0 в backend, >0 только в worker-pod** |
| `LLM_REQUEST_TIMEOUT_SECONDS`  | int    | `180`         | Timeout на один запрос                           |

## Sandbox (активная верификация)

| Переменная                | Тип                            | Default           | Описание                                          |
| ------------------------- | ------------------------------ | ----------------- | ------------------------------------------------- |
| `SANDBOX_TYPE`            | `""` / `docker` / `kubernetes` | `""` (выключен)   | Тип executor'а                                    |
| `SANDBOX_IMAGE`           | image-ref                      | образ из поставки | Образ с инструментами (nmap/curl/dig/nuclei/etc.) |
| `SANDBOX_TIMEOUT_SECONDS` | int                            | `120`             | Timeout на команду                                |
| `SANDBOX_OUTPUT_LIMIT_KB` | int                            | `10`              | Лимит stdout/stderr                               |
| `SANDBOX_NAMESPACE`       | string                         | —                 | K8s namespace (только для `kubernetes`)           |
| `SANDBOX_KUBECONFIG`      | path                           | —                 | Путь к kubeconfig (только для `kubernetes`)       |

## Feature flags

| Переменная                         | Тип  | Default | Описание                                     |
| ---------------------------------- | ---- | ------- | -------------------------------------------- |
| `FEATURE_FINDING_COPY`             | bool | `false` | Копирование finding в другие проекты (v0.8+) |
| `FEATURE_JIRA_REVERSE_SYNC`        | bool | `false` | См. Jira                                     |
| `FEATURE_AUTO_VERIFY_FIXES`        | bool | `false` | См. Jira                                     |
| `FEATURE_MANUAL_RESCAN`            | bool | `false` | UI-кнопки «Перепроверить» (project + finding); см. [20. Manual rescan](20-manual-rescan.md) |
| `FEATURE_SECURITY_HUB_INTEGRATION` | bool | `false` | См. Keycloak                                 |

## Manual rescan (Hub → сканер)

Эти переменные нужны только при `FEATURE_MANUAL_RESCAN=true`. Указывают backend'у, куда дёргать webhook'и сканеров.

| Переменная                     | Тип    | Default | Описание                                                                  |
| ------------------------------ | ------ | ------- | ------------------------------------------------------------------------- |
| `DOMAINSCOPE_RESCAN_URL`       | url    | —       | base URL DomainScope (без `/api/v1/rescan`), напр. `http://domainscope:8087` |
| `DOMAINSCOPE_RESCAN_API_KEY`   | string | —       | shared secret; должен совпадать с `RESCAN_API_KEY` на DomainScope         |
| `IAC_SCANNER_RESCAN_URL`       | url    | —       | base URL IaC-сканера, напр. `http://iac-scanner:8086`                     |
| `IAC_SCANNER_RESCAN_API_KEY`   | string | —       | shared secret; должен совпадать с `RESCAN_API_KEY` на IaC-сканере         |
| `RESCAN_TIMEOUT_SECONDS`       | int    | `10`    | Таймаут на HTTP-вызов webhook'а                                            |

## Background jobs (worker)

| Переменная                         | Тип  | Default     | Описание                          |
| ---------------------------------- | ---- | ----------- | --------------------------------- |
| `CLEANUP_SCHEDULE`                 | cron | `0 2 * * *` | Расписание очистки старых reports |
| `CLEANUP_RETENTION_COMPLETED_DAYS` | int  | `7`         | Хранение completed reports        |
| `CLEANUP_RETENTION_FAILED_DAYS`    | int  | `30`        | Хранение failed reports           |
| `CLEANUP_RETENTION_PENDING_DAYS`   | int  | `0`         | Pending не чистятся по умолчанию  |
| `CLEANUP_DRY_RUN`                  | bool | `false`     | Логировать, не удалять            |
| `REFRESH_CLEANUP_SCHEDULE`         | cron | `0 3 * * *` | Очистка истёкших refresh tokens   |
| `REFRESH_CLEANUP_RETENTION_DAYS`   | int  | `30`        | Сколько хранить revoked tokens    |

## Frontend (build-time)

| Переменная                  | Тип    | Default                 | Описание                                                          |
| --------------------------- | ------ | ----------------------- | ----------------------------------------------------------------- |
| `REACT_APP_API_URL`         | URL    | `http://localhost:8082` | API endpoint                                                      |
| `REACT_APP_NETBOX_BASE_URL` | URL    | —                       | Если задана — IP в карточке finding становятся ссылками на NetBox |
| `VERSION_XY`                | string | `0.0`                   | Major.Minor (из `./VERSION`)                                      |
| `GIT_COMMIT`                | string | `unknown`               | Short commit hash                                                 |

Frontend env vars инжектируются через `entrypoint.sh` (плейсхолдеры `__REACT_APP_*__` → реальные значения runtime).

## Логирование

| Переменная   | Тип                           | Default             | Описание          |
| ------------ | ----------------------------- | ------------------- | ----------------- |
| `LOG_LEVEL`  | `debug`/`info`/`warn`/`error` | `info`              | Уровень zap-логов |
| `LOG_FORMAT` | `json`/`console`              | `json` в production | Формат логов      |

## Минимальный production `.env`

```ini
APP_ENV=production

# DB
DB_HOST=postgres
DB_PORT=5432
DB_NAME=securityhub
DB_USER=securityhub
DB_PASSWORD=<random-32>

# JWT
JWT_SECRET=<openssl rand -hex 32>
ACCESS_TOKEN_TTL_MINUTES=15
REFRESH_TOKEN_TTL_DAYS=7

# Auth
AUTH_MODE=SSO
KEYCLOAK_URL=http://keycloak:8083
KEYCLOAK_PUBLIC_URL=https://keycloak.example.com
KEYCLOAK_REALM=securityhub
KEYCLOAK_CLIENT_ID=security-hub
KEYCLOAK_CLIENT_SECRET=<from-keycloak>

# URLs
FRONTEND_URL=https://hub.example.com
FRONTEND_BASE_URL=https://hub.example.com
REACT_APP_API_URL=https://hub.example.com
ALLOWED_ORIGINS=https://hub.example.com

# Notifications
DISPATCHER_WORKERS=10
TELEGRAM_NOTIFICATION_WORKERS=5
MATTERMOST_NOTIFICATION_WORKERS=10

# Jira (после ручной настройки в UI)
FEATURE_JIRA_REVERSE_SYNC=true
JIRA_REVERSE_SYNC_INTERVAL_MINUTES=60
FEATURE_AUTO_VERIFY_FIXES=true

# LLM (если есть провайдер)
LLM_BASE_URL=https://api.your-llm.com/v1
LLM_API_KEY=<secret>
LLM_MODEL=glm-4-plus
LLM_WORKERS=0      # backend; в worker-pod задайте >0

# Sandbox (только в worker)
SANDBOX_TYPE=docker
SANDBOX_IMAGE=your-registry/sandbox-tools:latest
```

## Чтение текущей конфигурации

```bash
# Compose
docker compose exec backend env | grep -E '^(DB_|JWT_|KC_|KEYCLOAK_|FEATURE_|JIRA_|LLM_|SANDBOX_)'

# Kubernetes
kubectl -n hub get deploy hub-security-scan-hub-backend -o yaml | grep -A2 'env:'

# bare-metal
sudo systemctl cat hub-backend | grep EnvironmentFile
cat /opt/hub/config/hub.env
```

## Изменение конфигурации

После любого изменения env vars:

- **Compose**: `docker compose restart backend worker`
- **Kubernetes**: helm upgrade — pods пересоздадутся
- **bare-metal**: `sudo systemctl restart hub-backend hub-worker`

# 01. Обзор архитектуры

## Что такое Security Hub

Security Hub (далее — **Hub**) — платформа управления уязвимостями (vulnerability management). Принимает результаты сканирования от внешних сканеров в формате SARIF, дедуплицирует находки, маршрутизирует их в Jira/уведомления, отслеживает жизненный цикл (open → confirmed → fixed → verified) и предоставляет UI для аналитика и руководства.

**DomainScope** — отдельный сервис непрерывного мониторинга атакуемой поверхности. Сканирует периметр (subfinder, DNS, nmap, nuclei, OpenVAS, TLSX, OWASP ZAP), складывает результаты в собственную БД и опционально отдаёт находки в Hub в формате SARIF + предлагает новые scope-записи через API.

## Компоненты

```
┌────────────────────────────── Security Hub ──────────────────────────────┐
│                                                                          │
│  ┌──────────┐   ┌────────────┐   ┌──────────┐   ┌─────────────┐          │
│  │ frontend │──▶│  backend   │──▶│ postgres │   │  job queue  │          │
│  │  React   │   │   Go/Gin   │   │    15    │◀──│  (jobs)     │          │
│  └──────────┘   └─────┬──────┘   └──────────┘   └─────┬───────┘          │
│       │               │                               │                  │
│       │               ▼                               ▼                  │
│       │       ┌───────────────┐               ┌──────────────┐           │
│       │       │ keycloak OIDC │               │  worker (Go) │           │
│       │       └───────────────┘               │ jira/notify/ │           │
│       │                                       │  llm/cleanup │           │
│       │                                       └──────────────┘           │
│       │                                                                  │
│       └──── /version, /api/v1/* ─────▶ external clients                  │
└──────────────────────────────────────────────────────────────────────────┘

         ▲                                       │
         │ SARIF upload (API key)                │ Outbound API calls
         │                                       │ (REST / Bot API / incoming webhook)
┌────────┴─────────┐                             ▼
│   DomainScope    │                   ┌──────────────────────┐
│   subfinder      │                   │  Jira / Mattermost   │
│   nmap/nuclei    │                   │  Telegram / NetBox   │
│   openvas/zap    │                   │  LLM provider        │
└──────────────────┘                   └──────────────────────┘
```

### Сервисы Hub

| Сервис     | Назначение                                             | Технология         | Порт (default) |
| ---------- | ------------------------------------------------------ | ------------------ | -------------- |
| `backend`  | REST API, RBAC, бизнес-логика                          | Go + Gin           | 8082           |
| `worker`   | Async jobs: Jira sync, уведомления, LLM-триаж, cleanup | Go (async jobs)   | —              |
| `frontend` | Web UI                                                 | React + AntD + Bun | 3000           |
| `postgres` | Основная БД                                            | PostgreSQL 15      | 5432           |
| `grafana`  | Метрики (опционально)                                  | Grafana 11.4       | 8084           |
| `keycloak` | SSO провайдер (внешний или сосед)                      | Keycloak 24.0.5    | 8083           |

### Сервисы DomainScope

| Сервис           | Назначение                                                           |
| ---------------- | -------------------------------------------------------------------- |
| `domain-scope`   | Daemon, выполняющий циклы discovery/portscan/nuclei/openvas/tlsx/zap |
| `postgres`       | Своя БД (отдельный инстанс, не общий с Hub)                          |
| `openvas` (опц.) | Greenbone gvmd/gsad/ospd/pg-gvm/redis — CVE-сканер                   |
| `zap` (опц.)     | OWASP ZAP daemon — активный web-сканер                               |

## Поток данных

### Сценарий 1: внешний сканер шлёт SARIF

1. Внешний CI (например, GitLab job) скачивает SARIF из своего сканера
2. Шлёт `POST /api/v1/products/<id>/reports` c заголовком `Authorization: Bearer <api_key>`
3. Backend парсит SARIF (с hard-лимитами), дедуплицирует findings по `dedup_hash`, открывает новые/обновляет существующие
4. Worker асинхронно: создаёт Jira-тикеты (если включена автоматизация), шлёт уведомления, опционально передаёт finding в LLM-триаж
5. Аналитик видит findings в UI, может закрыть, отметить как false-positive, передать в Jira

### Сценарий 2: DomainScope обнаруживает новый домен

1. DomainScope-daemon запускает discovery-цикл (subfinder + DNS) на seed-домены из своего конфига или из NetBox/Hub
2. Новые домены/IP сохраняются в БД DomainScope с указанием `source` (subfinder / netbox_dns / scope_entry / tls_san)
3. Если включён `sarif_auto_upload`, DomainScope формирует SARIF и шлёт в Hub как обычный SARIF-report
4. Если включены scope-proposals, DomainScope шлёт `POST /api/v1/projects/<id>/scope/proposals` — админ Hub'a видит предложение в UI и подтверждает добавление в periметр

### Сценарий 3: пользователь логинится через SSO

Hub поддерживает мульти-провайдерный SSO: Keycloak (по умолчанию), Azure AD (Entra ID) и любой другой OIDC-провайдер — см. [`06-integration-keycloak.md`](06-integration-keycloak.md).

1. Браузер → `/login` → Hub редиректит в выбранный OIDC-провайдер (authorization code flow)
2. Юзер логинится в IdP, возвращается с `code`
3. Backend обменивает `code` на tokens → создаёт/обновляет юзера в БД → выпускает внутренний JWT (access + refresh)
4. Все последующие запросы — с `Authorization: Bearer <access_token>`

## Безопасность

- **Мульти-провайдерный SSO** — Keycloak (по умолчанию), Azure AD (Entra ID) и любой OIDC-провайдер через `SSO_PROVIDERS` / `OIDC_<NAME>_*`
- **Casbin RBAC** — авторизация на уровне ресурсов (project/product/finding) и действий (read/write/delete/admin)
- **Service accounts** — машинные клиенты с API-key (для CI и внешних сканеров); ключ хешируется в БД, prefix виден для аудита
- **SSRF-защита** — Jira/SARIF/NetBox клиенты блокируют приватные сети по умолчанию (`JIRA_ALLOW_LOCAL_DIAL=false`)
- **SARIF hard limits** — максимум 100 runs, 100k results на run, max 1 MiB строка, JSON depth 64
- **Sandbox для LLM-проверок** — изоляция через docker/k8s, allowlist команд, лимит stdout

## Версионирование

Все компоненты Hub публикуются как монорепо с единой версией формата `X.Y.BUILD+COMMIT` (например, `0.9.20260602093200+a1b2c3d`):

- **X.Y** — мажор/минор, общий для всех компонентов
- **BUILD** — UTC-метка `YYYYMMDDHHMMSS` сборки
- **COMMIT** — короткий git-hash

DomainScope версионируется независимо (см. `domainscope/VERSION`).

Подробнее: [`18-upgrades.md`](18-upgrades.md).

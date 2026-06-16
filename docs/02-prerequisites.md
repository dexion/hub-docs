# 02. Системные требования

## Аппаратные требования

### Минимум (pilot, до 10 пользователей, до 50k findings)

| Компонент            | CPU         | RAM       | Disk       |
| -------------------- | ----------- | --------- | ---------- |
| Hub backend          | 1 vCPU      | 1 GB      | —          |
| Hub worker           | 0.5 vCPU    | 512 MB    | —          |
| Hub frontend (nginx) | 0.25 vCPU   | 128 MB    | —          |
| PostgreSQL (Hub)     | 1 vCPU      | 1 GB      | 20 GB      |
| Keycloak             | 1 vCPU      | 1 GB      | 5 GB       |
| **Итого Hub**        | **~4 vCPU** | **~4 GB** | **~30 GB** |

DomainScope (если разворачивается рядом):

| Компонент                | CPU    | RAM  | Disk          |
| ------------------------ | ------ | ---- | ------------- |
| DomainScope daemon       | 1 vCPU | 1 GB | —             |
| PostgreSQL (DomainScope) | 1 vCPU | 1 GB | 20 GB         |
| **+ OpenVAS** (опц.)     | 2 vCPU | 6 GB | 30 GB (feeds) |
| **+ OWASP ZAP** (опц.)   | 1 vCPU | 2 GB | 5 GB          |

### Production (100+ пользователей, миллионы findings)

| Компонент               | CPU             | RAM        | Disk        |
| ----------------------- | --------------- | ---------- | ----------- |
| Hub backend (×2 для HA) | 2 vCPU          | 2 GB       | —           |
| Hub worker (×2)         | 1 vCPU          | 1 GB       | —           |
| PostgreSQL (Hub)        | 4 vCPU          | 8 GB       | 100 GB SSD  |
| Keycloak (×2 для HA)    | 2 vCPU          | 2 GB       | —           |
| Keycloak DB             | 2 vCPU          | 2 GB       | 20 GB       |
| **Итого Hub**           | **~12-16 vCPU** | **~20 GB** | **~150 GB** |

> Реальное потребление зависит от количества SARIF-загрузок в день и размера отчётов. После 6 месяцев работы наблюдайте за метриками БД и масштабируйте по диску/RAM PostgreSQL.

## Операционная система

### Docker Compose / Bare-metal

| OS                  | Версия               | Поддержка                  |
| ------------------- | -------------------- | -------------------------- |
| Ubuntu              | 22.04 LTS, 24.04 LTS | ✅ Production              |
| Debian              | 12 (Bookworm)        | ✅ Production              |
| RHEL / Rocky / Alma | 9                    | ✅ Production              |
| Astra Linux         | 1.7 SE               | ✅ (использовано на проде) |
| macOS               | 14+                  | ⚠️ только dev              |
| Windows             | —                    | ❌                         |

### Kubernetes

- **k3s** v1.30+ (рекомендуется для on-premise одно-нодовых кластеров)
- **Vanilla k8s** v1.28+ — поддерживается
- **OpenShift** — не проверялось

## Программное обеспечение

| Software       | Минимум           | Где нужно                                |
| -------------- | ----------------- | ---------------------------------------- |
| Docker Engine  | 24.0+             | Compose deploy, dev                      |
| Docker Compose | v2.20+ (plugin)   | Compose deploy                           |
| Helm           | 3.13+             | K8s deploy                               |
| kubectl        | соответствует k8s | K8s deploy                               |
| `make`         | GNU 4.0+          | Bare-metal/dev                           |
| Go             | 1.26+             | Только для сборки из исходников          |
| Bun            | 1.0+              | Только для сборки frontend из исходников |
| Git            | 2.30+             | Для CI и сборки                          |

## Сетевые требования

### Порты, открытые наружу (production)

| Порт | Назначение                         | Куда смотрит     |
| ---- | ---------------------------------- | ---------------- |
| 443  | Веб-UI и API (через nginx/traefik) | Все пользователи |
| 80   | HTTP → редирект на 443             | Все пользователи |

### Внутренние порты (между сервисами)

| Порт | Сервис                   | Кто использует                          |
| ---- | ------------------------ | --------------------------------------- |
| 5432 | PostgreSQL (Hub)         | backend, worker                         |
| 5432 | PostgreSQL (DomainScope) | domain-scope (отдельный инстанс!)       |
| 8082 | Hub backend              | frontend, внешние клиенты SARIF         |
| 8083 | Keycloak                 | backend, frontend (через reverse-proxy) |
| 8084 | Grafana                  | админ                                   |
| 9390 | OpenVAS GMP              | DomainScope                             |
| 8080 | OWASP ZAP daemon         | DomainScope                             |

### Исходящий трафик

| Адресат            | Зачем               | Можно ли через прокси |
| ------------------ | ------------------- | --------------------- |
| Docker Hub / GHCR  | Образы              | Да (HTTPS_PROXY)      |
| Keycloak realm     | OIDC discovery      | Если Keycloak внешний |
| Jira instance      | Создание тикетов    | Да                    |
| Telegram Bot API   | Уведомления         | Да                    |
| Mattermost webhook | Уведомления         | Да                    |
| NetBox             | Sync периметра      | Да                    |
| LLM провайдер      | AI-триаж            | Да (`LLM_BASE_URL`)   |
| Nuclei templates   | Обновление          | Да                    |
| OpenVAS feeds      | Обновление CVE-базы | Да                    |

> **Air-gapped окружение**: возможно, но требует ручной загрузки образов в private-registry (например, Harbor) и зеркалирования Nuclei/OpenVAS feeds.

## Доменные имена и TLS

### Production

Для боевого стенда понадобятся следующие FQDN (примеры для домена `hub.example.com`):

| FQDN                                 | Назначение                                     |
| ------------------------------------ | ---------------------------------------------- |
| `hub.example.com`                    | Основной UI Hub                                |
| `keycloak.hub.example.com`           | Keycloak (или путь `/auth` на основном домене) |
| `openvas.hub.example.com` (опц.)     | OpenVAS Web UI                                 |
| `domainscope.hub.example.com` (опц.) | DomainScope API                                |

### Сертификаты

- **Let's Encrypt** — поддерживается через cert-manager в K8s или certbot в bare-metal
- **Внутренний CA** — поддерживается; примонтируйте корневые сертификаты в `/etc/ssl/certs` и установите `SSL_CERT_DIR` (Go), `NODE_EXTRA_CA_CERTS` (frontend build)
- **Self-signed** — допустимо только для dev. На production будут проблемы с OIDC discovery и webhook delivery.

## Postgres

- **Только PostgreSQL 15+** (на 14 миграции не тестировались)
- Включить расширение `uuid-ossp` (миграция сделает это сама)
- Рекомендуемые параметры для production:

```ini
shared_buffers = 2GB
effective_cache_size = 6GB
maintenance_work_mem = 512MB
work_mem = 32MB
max_connections = 200
```

- Регулярный `VACUUM ANALYZE` — желательно через autovacuum (включён по умолчанию)

## Backup-инфраструктура

Для production обязательны:

1. **Снэпшоты PostgreSQL** — ежедневно, ретенция минимум 14 дней
2. **Volume snapshots** для `storage/` (отчёты, артефакты) — ежедневно
3. **Secret backup** — Vault snapshots
4. **Backup-тест** — раз в квартал восстановите из backup на staging и проверьте, что Hub стартует и видит данные

Подробнее: [`17-operations.md`](17-operations.md).

## Что нужно подготовить ДО установки

Чеклист:

- [ ] Виртуалка / k8s-кластер с указанными ресурсами
- [ ] OS, Docker/Helm установлены и обновлены
- [ ] DNS-записи прописаны и резолвятся
- [ ] TLS-сертификаты (Let's Encrypt account или wildcard cert)
- [ ] Доступ к Docker Hub / private registry (Harbor)
- [ ] Keycloak instance (внешний) ИЛИ подготовлены параметры для встроенного Keycloak
- [ ] Внешняя БД PostgreSQL (если не используете встроенную) с пустыми БД для Hub и DomainScope
- [ ] SMTP/Telegram/Mattermost (если нужны уведомления)
- [ ] Jira account для бота интеграции (если нужна Jira)
- [ ] План бэкапов согласован

После выполнения чеклиста — переходите к выбранному сценарию развёртывания.

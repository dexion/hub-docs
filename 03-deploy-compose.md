# 03. Развёртывание через Docker Compose

Самый быстрый путь к работающему Hub. Подходит для пилотов, dev-стендов и продакшен-инсталляций без Kubernetes.

> Поставка — готовые Docker-образы из публичного registry. Сборка из исходников не предполагается.

## Предусловия

- Виртуалка/железо по требованиям из [`02-prerequisites.md`](02-prerequisites.md)
- Docker Engine 24+ и Docker Compose v2.20+ (`docker compose version`)
- 30+ ГБ свободного диска
- Доступ к публичному Docker registry (или внутреннему зеркалу)

## 1. Получение артефактов поставки

В пакете поставки админу выдаются:

| Файл                                 | Назначение                             |
| ------------------------------------ | -------------------------------------- |
| `docker-compose.yml`                 | Compose-стек со ссылками на образы Hub |
| `.env.example`                       | Шаблон конфигурации                    |
| `docker-compose-keycloak.yml` (опц.) | Дополнительный compose для Keycloak    |
| `nginx.conf.example` (опц.)          | Шаблон reverse-proxy                   |

Положите файлы в любую рабочую директорию, например `/opt/hub/`:

```bash
sudo mkdir -p /opt/hub
sudo cp docker-compose.yml .env.example /opt/hub/
cd /opt/hub
```

## 2. Конфигурация `.env`

```bash
cp .env.example .env
```

Минимальный набор для запуска (отредактируйте `.env`):

```ini
# === Database ===
DB_PASSWORD=<strong-random-password-32-chars>

# === JWT ===
JWT_SECRET=<openssl rand -hex 32>

# === Frontend / API URLs ===
FRONTEND_URL=https://hub.example.com
REACT_APP_API_URL=https://hub.example.com
ALLOWED_ORIGINS=https://hub.example.com

# === Auth mode ===
AUTH_MODE=LOCAL
LOCAL_ADMIN_PASSWORD=<strong-admin-password>

# === App env ===
APP_ENV=production
```

> **WARNING:** дефолтные значения `JWT_SECRET` и `LOCAL_ADMIN_PASSWORD` из шаблона **не использовать в продакшене** — задайте свои случайные значения.

Полный справочник переменных: [`05-configuration.md`](05-configuration.md).

## 3. Pull образов и запуск

```bash
docker compose pull
docker compose up -d
```

Все образы Hub поставляются с тегом `:latest` — обновление до новой версии происходит автоматически при `docker compose pull`.

Стек поднимает (компоненты):

| Сервис     | Назначение             | Образ (Docker Hub)             | Порт хоста |
| ---------- | ---------------------- | ------------------------------ | ---------- |
| `postgres` | БД Hub (PostgreSQL 15) | `postgres:15`                  | 5432       |
| `backend`  | REST API               | `dexionius/sshub-backend:latest`  | 8082       |
| `worker`   | Async jobs             | `dexionius/sshub-worker:latest`   | —          |
| `frontend` | Web UI                 | `dexionius/sshub-frontend:latest` | 3000       |
| `grafana`  | Метрики (опц.)         | `grafana/grafana:11.4.0`       | 8084       |

### Закрытый контур / внутренний registry

Если внешний registry недоступен, выгрузите образы во внутренний (например, Harbor). В `.env` задайте префикс:

```ini
HUB_IMAGE_REGISTRY=registry.internal.example.com/securityhub
```

`docker-compose.yml` собирает ref как `${HUB_IMAGE_REGISTRY}/sshub-backend:latest`. Все нужные образы перед использованием залейте в свой registry стандартным `docker tag` + `docker push`.

## 4. Проверка

После `docker compose up -d` подождите ~30 секунд (миграции БД стартуют автоматически):

```bash
# Backend жив
curl http://localhost:8082/api/v1/version
# Frontend отвечает
curl -I http://localhost:3000
```

Откройте `http://localhost:3000` в браузере. Войдите как `admin@localhost.local` / значение `LOCAL_ADMIN_PASSWORD`.

### Swagger / OpenAPI

Hub отдаёт интерактивную документацию API:

```
https://hub.example.com/swagger/index.html
```

(локально — `http://localhost:8082/swagger/index.html`). Удобно для отладки интеграций и проверки контрактов.

## 5. Reverse proxy и TLS (production)

Compose стек слушает на голых портах. Для production поставьте перед ним nginx/traefik/caddy с TLS.

### Пример nginx

```nginx
server {
    listen 443 ssl http2;
    server_name hub.example.com;

    ssl_certificate     /etc/letsencrypt/live/hub.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/hub.example.com/privkey.pem;

    client_max_body_size 100M;  # SARIF-отчёты бывают большими

    location /api/ {
        proxy_pass http://127.0.0.1:8082;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /swagger/ {
        proxy_pass http://127.0.0.1:8082;
    }

    location /version {
        proxy_pass http://127.0.0.1:8082;
    }

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
    }
}

server {
    listen 80;
    server_name hub.example.com;
    return 301 https://$host$request_uri;
}
```

## 6. Service-сценарии

### Запуск Keycloak рядом

Если SSO нужно, используйте дополнительный compose:

```bash
docker compose -f docker-compose.yml -f docker-compose-keycloak.yml up -d
```

Дальнейшая настройка realm/client — см. [`06-integration-keycloak.md`](06-integration-keycloak.md).

## 7. Управление

```bash
# Логи
docker compose logs -f                # все
docker compose logs -f backend

# Перезапуск (например, после изменения env)
docker compose restart backend worker

# Остановка
docker compose down

# Обновление до новой :latest
docker compose pull
docker compose up -d

# Версия
curl http://localhost:8082/version
```

## 8. Persistence

| Что                | Где                           |
| ------------------ | ----------------------------- |
| БД Hub             | docker volume `postgres_data` |
| Артефакты/отчёты   | `./storage` (bind mount)      |
| Логи               | `./logs` (bind mount)         |
| Grafana dashboards | docker volume `grafana_data`  |

Backup БД:

```bash
docker compose exec postgres pg_dump -U securityhub securityhub | gzip > backup-$(date +%Y%m%d).sql.gz
```

Restore:

```bash
gunzip -c backup-20260601.sql.gz | docker compose exec -T postgres psql -U securityhub securityhub
```

## 9. Обновление

```bash
cd /opt/hub
docker compose pull
docker compose up -d
```

Миграции БД применяются автоматически при старте backend. Подробнее: [`18-upgrades.md`](18-upgrades.md).

## Типовые проблемы

| Симптом                 | Что проверить                                                                     |
| ----------------------- | --------------------------------------------------------------------------------- |
| Backend в crash-loop    | `docker compose logs backend` — обычно отсутствует `JWT_SECRET` или БД недоступна |
| Frontend 502            | Backend не стартует или `REACT_APP_API_URL` указан неверно                        |
| SARIF upload 413        | Увеличьте `client_max_body_size` в nginx                                          |
| Миграции не применяются | Проверьте `DB_*` env vars; ошибки в backend-логах                                 |
| `docker pull denied`    | Не залогинены в registry. `docker login <registry>`                               |

Полный troubleshooting: [`19-troubleshooting.md`](19-troubleshooting.md).

# 06. Интеграция с Keycloak (SSO)

Hub использует Keycloak как OIDC-провайдер. Поддерживается два режима:

1. **SSO-логин в UI** — пользователь входит через Keycloak realm, Hub выпускает свой внутренний JWT
2. **Transparent SSO** — внешнее приложение проксирует запросы в Hub с собственным JWT того же Keycloak realm; Hub валидирует и принимает без повторного логина

## Архитектура

```
                    ┌───────────────┐
                    │   Browser     │
                    └───────┬───────┘
                            │ 1. /auth/keycloak/login
                            ▼
                  ┌─────────────────┐
                  │  Hub backend    │ ── 2. redirect to KC ──▶  ┌──────────┐
                  │                 │                           │ Keycloak │
                  │                 │ ◀── 3. code via redirect ─│ realm    │
                  │                 │                           └──────────┘
                  │                 │ ── 4. exchange code → KC tokens
                  │                 │ ── 5. create/update user in DB
                  │                 │ ── 6. issue internal JWT
                  └─────────────────┘
```

## Сценарий A: Keycloak в одном compose c Hub

Самый простой для пилотов. Используется `docker-compose-keycloak.yml`.

### Запуск

```bash
docker compose -f docker-compose.yml -f docker-compose-keycloak.yml up -d
```

Поднимется Keycloak 24.0.5 на порту 8083.

### Настройка realm

После старта Keycloak — настройте realm и client вручную (см. ниже) или используйте скрипт настройки из комплекта поставки (если предоставлен).

Скрипт настройки realm/client может быть в комплекте поставки. Если нет — настройте Keycloak вручную (см. ниже «Что админ настраивает в Keycloak»).

### Hub env vars

```ini
AUTH_MODE=SSO

KEYCLOAK_URL=http://keycloak:8083                 # внутренний URL для backend
KEYCLOAK_PUBLIC_URL=http://localhost:8083         # внешний URL для браузера
KEYCLOAK_REALM=securityhub
KEYCLOAK_CLIENT_ID=security-hub
KEYCLOAK_CLIENT_SECRET=<скопировать из Keycloak UI: Clients → security-hub → Credentials>
```

Перезапустите backend: `docker compose restart backend`.

## Сценарий B: внешний Keycloak (production)

Стандартный продакшен — Keycloak уже развёрнут отдельно, Hub только использует.

### Что админ настраивает в Keycloak

#### 1. Realm

Создать или использовать существующий. Имя — например `securityhub`.

#### 2. Client `security-hub`

- **Client type:** OpenID Connect
- **Client ID:** `security-hub`
- **Client authentication:** ON (confidential)
- **Authorization:** OFF
- **Authentication flow:**
  - ✅ Standard flow
  - ❌ Implicit, Direct access, OAuth Device, Service account
- **Valid Redirect URIs:** `https://hub.example.com/*`
- **Valid post logout redirect URIs:** `https://hub.example.com/*`
- **Web origins:** `https://hub.example.com`

После создания — закладка `Credentials` → скопировать `Client Secret`.

#### 3. Роли

Realm-roles (рекомендуется):

- `admin` — полный доступ
- `project_owner` — управление проектами и продуктами
- `security_analyst` — работа с findings
- `developer` — read + комментарии
- `viewer` — read-only
- `auditor` — read-only + экспорт

Маппинг ролей на Hub-permissions делается через Casbin policies в БД Hub.

#### 4. Mappers

В Client → Client Scopes → Dedicated scope → Mappers добавить:

- **Audience mapper** — `aud=security-hub` в access token
  - Mapper Type: Audience
  - Included Client Audience: `security-hub`
  - Add to access token: ON

- (опционально) **Group membership** — если используете группы для ролей

#### 5. TLS

В production realm должен быть на HTTPS:

```bash
kcadm.sh update realms/securityhub -s sslRequired=EXTERNAL
```

Для dev можно `sslRequired=NONE`, но Hub в `APP_ENV=production` откажется работать с HTTP-Keycloak.

### Hub env vars

```ini
AUTH_MODE=SSO

# Backend → Keycloak (внутренний)
KEYCLOAK_URL=https://keycloak-internal.example.com    # или прямой K8s service URL
KEYCLOAK_PUBLIC_URL=https://keycloak.example.com      # куда редиректится браузер
KEYCLOAK_REALM=securityhub
KEYCLOAK_CLIENT_ID=security-hub
KEYCLOAK_CLIENT_SECRET=<из Keycloak>
```

### Split-network (Docker/K8s)

Если backend ходит к Keycloak по internal service-name, а браузер — по публичному FQDN, и OIDC discovery возвращает internal URL, переопределите endpoints явно:

```ini
KEYCLOAK_JWKS_URL=https://keycloak.example.com/realms/securityhub/protocol/openid-connect/certs
KEYCLOAK_TOKEN_URL=https://keycloak.example.com/realms/securityhub/protocol/openid-connect/token
```

В `APP_ENV=production` оба обязаны быть HTTPS.

## Сценарий C: Transparent SSO (внешний JWT)

Используется, когда стороннее приложение (например, security-портал на базе того же Keycloak) проксирует запросы к Hub с собственным JWT и хочет, чтобы Hub его принимал без повторного логина.

### Включение

```ini
FEATURE_SECURITY_HUB_INTEGRATION=true

KC_JWKS_URL=https://keycloak.example.com/realms/securityhub/protocol/openid-connect/certs
KC_ISSUER=https://keycloak.example.com/realms/securityhub
KC_AUDIENCES=external-app-1,external-app-2
KC_AUTO_PROVISION=true     # автосоздавать юзера при первом запросе

ATOM_IDP_BASE_URL=https://idp.example.com   # для CORS
```

### Поток валидации

При запросе с `Authorization: Bearer <external-jwt>`:

1. Hub валидирует подпись через `KC_JWKS_URL` (с кэшем JWKS)
2. Проверяет `iss == KC_ISSUER`
3. Проверяет `aud ∈ KC_AUDIENCES` (любое из comma-separated)
4. Проверяет `exp > now`
5. Ищет юзера в БД:
   - По `keycloak_id` (sub из JWT)
   - По `email` (только если `email_verified=true`)
   - Если не найден и `KC_AUTO_PROVISION=true` → создаёт нового без ролей

### WARNING: aud=account

В Keycloak `account` — built-in client (для UI самого Keycloak). По умолчанию access token от любого realm-юзера может включать `aud=account`. **Не добавляйте `account` в `KC_AUDIENCES` в production** — это сделает Hub доступным для любого пользователя realm без проверки целевой аудитории.

Используйте отдельные `aud`-значения для каждого внешнего приложения и Audience mappers в их Keycloak-клиентах.

## Audience mapper для atom-idp

Если интегрируетесь с atom-idp:

1. В Keycloak atom-idp создайте Audience mapper: `aud=security-hub`
2. На Hub задайте:

```ini
KC_AUDIENCES=security-hub
ATOM_IDP_BASE_URL=https://atom-idp.example.com
```

## Auto-provisioning

При `KC_AUTO_PROVISION=true`:

- Новый юзер создаётся с `email`, `username`, `keycloak_id` из JWT
- **Без ролей** — для доступа админ должен назначить роль через UI Hub → Admin → Users
- Без email юзер не создаётся (логируется warning)

При `KC_AUTO_PROVISION=false`: внешние JWT принимаются только для уже существующих юзеров.

## Откат к LOCAL-режиму

Если SSO сломался (например, Keycloak недоступен), временно вернитесь на LOCAL:

```ini
AUTH_MODE=LOCAL
LOCAL_ADMIN_PASSWORD=<пароль>
```

```bash
docker compose restart backend
# Войдите как admin@localhost.local / LOCAL_ADMIN_PASSWORD
```

После починки SSO — верните `AUTH_MODE=SSO`. Существующие SSO-пользователи в БД сохранятся.

## Проверка интеграции

```bash
# 1. Discovery должен быть доступен из backend
docker compose exec backend curl -fs \
  $KEYCLOAK_URL/realms/$KEYCLOAK_REALM/.well-known/openid-configuration | jq

# 2. JWKS отдаёт ключи
curl -fs $KEYCLOAK_PUBLIC_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/certs | jq '.keys[0].kid'

# 3. UI редиректит на Keycloak
curl -sI https://hub.example.com/auth/keycloak/login | grep Location

# 4. Логи backend при логине
docker compose logs -f backend | grep -i keycloak
```

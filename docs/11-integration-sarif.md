# 11. Внешние сканеры (SARIF Upload)

Любой сканер, который умеет выгружать SARIF 2.1.0, может загружать результаты в Hub. Поддерживаются gosec, semgrep, kics, trivy, nuclei, OWASP ZAP, custom-сканеры — формат стандартный.

## Архитектура

```
External scanner (gosec / semgrep / etc.)
        │
        │ produces SARIF 2.1.0 (.sarif или .json)
        ▼
   CI job (GitLab / GitHub Actions)
        │
        │ POST /api/v1/products/<id>/reports
        │ X-API-Key: <api-key>
        │ multipart/form-data: file=@scan.sarif
        ▼
   Hub backend
        │
        ├─ Парсит SARIF (с hard-лимитами)
        ├─ Извлекает results (findings)
        ├─ Дедуплицирует по dedup_hash (rule_id + location + ...)
        ├─ Создаёт новые / обновляет существующие findings
        └─ Возвращает report ID + counts
```

## Создание Service Account

Для CI/сканеров нужны не пользователи, а машинные клиенты. Service account имеет:

- Имя и описание
- Один или несколько API keys
- Permissions на конкретные projects / products
- Scope `upload_report` (default) — может только заливать отчёты

### Через UI Hub

1. **Admin → Service Accounts → Create**
   - Name: `gitlab-ci-backend`
   - Description: `Auto-upload SARIF from backend CI`
2. **Service Account → API Keys → Add**
   - Name: `key-prod-1`
   - Expires: например, +180 дней (рекомендуется)
   - **Scope:** `upload_report`
   - Permissions: Project `Backend` → Product `backend-api`
3. Hub покажет полный ключ **один раз**. Скопируйте сразу и положите в CI variables (GitLab CI/CD Variables → masked, protected).

### Через API

```bash
# 1. Create SA
SA_ID=$(curl -X POST https://hub.example.com/api/v1/service-accounts \
  -H "Authorization: Bearer $ADMIN_JWT" \
  -H "Content-Type: application/json" \
  -d '{"name":"gitlab-ci-backend","description":"Auto-upload SARIF"}' \
  | jq -r '.data.id')

# 2. Create API Key
curl -X POST "https://hub.example.com/api/v1/service-accounts/$SA_ID/keys" \
  -H "Authorization: Bearer $ADMIN_JWT" \
  -H "Content-Type: application/json" \
  -d '{"name":"key-prod-1","expires_in_days":180}' \
  | jq
```

Ответ:

```json
{
  "data": {
    "id": "uuid",
    "name": "key-prod-1",
    "key": "sa_1a2b3c4d_AAA...full-key-shown-once...ZZZ",
    "prefix": "1a2b3c4d",
    "expires_at": "2026-12-02T...",
    "created_at": "2026-06-05T..."
  }
}
```

Формат ключа: `sa_<8hex>_<base64url>` (`sa` — фиксированный префикс, `<8hex>` — первые 4 байта в hex, `<base64url>` — секрет). Поле `prefix` (те самые 8 hex-символов) хранится в БД для аудита (можно отслеживать, какой ключ использовался). Полный ключ хешируется (SHA-256) и сравнивается при каждом запросе.

### Permissions

Service account по умолчанию **не имеет прав ни на что**. Назначьте через UI:

- Project-level: SA может заливать в любой product этого проекта
- Product-level: SA может заливать только в указанный product

## Endpoint загрузки SARIF

```
POST /api/v1/products/<product_id>/reports
X-API-Key: <api-key>
Content-Type: multipart/form-data
```

### Поля формы

Handler читает только перечисленные ниже поля. Файл должен иметь расширение `.sarif` или `.json` — никакие другие (включая `.gz`) не принимаются.

| Поле             | Тип    | Required | Описание                                                           |
| ---------------- | ------ | -------- | ------------------------------------------------------------------ |
| `file`           | file   | ✅       | SARIF-файл (`.sarif` или `.json`, без сжатия)                       |
| `engine`         | string | optional | Если SARIF не указывает tool — задайте явно                        |
| `engine_version` | string | optional | Версия сканера (если SARIF не содержит)                            |
| `verify_fixes`   | bool   | optional | См. [`07-integration-jira.md`](07-integration-jira.md) auto-verify |
| `commit_id`      | string | optional | Git commit SHA (приоритет ниже, чем header)                        |

> Поле формы `branch` handler-ом не читается и игнорируется. Передавать его не нужно.

### Заголовки

| Заголовок                           | Описание                                    |
| ----------------------------------- | ------------------------------------------- |
| `X-API-Key: <key>`                  | API key сервисного аккаунта (основной способ) |
| `X-Commit-Id: <sha>`                | Альтернатива form-полю                       |
| `Content-Type: multipart/form-data` | Стандарт                                     |

### Аутентификация

Service-account API-ключи передаются через `X-API-Key`. **Не** используйте `Authorization: Bearer <api-key>` — заголовок `Bearer` валидируется как JWT, и ключ `sa_...` будет отклонён с `401`.

Поддерживается также форма:

```
Authorization: ApiKey <key>
```

(JWT-пользователи, в отличие от сервисных аккаунтов, аутентифицируются через `Authorization: Bearer <jwt_token>`.)

## Поддерживаемые SARIF поля

Hub извлекает следующие поля стандарта 2.1.0:

| SARIF поле                                     | Hub field                          | Комментарий                                                   |
| ---------------------------------------------- | ---------------------------------- | ------------------------------------------------------------- |
| `runs[].tool.driver.name`                      | `findings.engine`                  | Например, `gosec`, `semgrep`                                  |
| `runs[].results[].ruleId`                      | `findings.rule_id`                 |                                                               |
| `runs[].results[].message.text`                | `findings.description`             |                                                               |
| `runs[].results[].level`                       | используется для severity fallback | `error`/`warning`/`note`                                      |
| `runs[].results[].locations[]`                 | `findings.location`                | physicalLocation, logicalLocations                            |
| `runs[].results[].properties.severity`         | `findings.severity`                | приоритет №1 для severity                                     |
| `runs[].results[].baselineState`               | `findings.baseline_state`          | `new`/`unchanged`/`updated`/`absent`                          |
| `runs[].results[].suppressions[].status`       | `findings.suppressed`              | `accepted` → `true`                                           |
| `runs[].results[].kind`                        | `findings.kind`                    | `fail`/`pass`/`open`/`review`/`notApplicable`/`informational` |
| `runs[].results[].codeFlows[]`                 | сохраняется                        | детали для UI                                                 |
| `runs[].results[].fixes[]`                     | сохраняется                        | предложенные фиксы                                            |
| `runs[].results[].taxonomies[]`                | сохраняется                        | CWE/OWASP mapping                                             |
| `runs[].versionControlProvenance[].revisionId` | используется как commit_id         | приоритет №2                                                  |

### Severity fallback (порядок приоритета)

1. `result.properties.severity` (явное поле)
2. `result.level` (`error` → HIGH, `warning` → MEDIUM, `note` → LOW)
3. `tool.driver.rules[ruleID].defaultConfiguration.level`
4. `"INFO"` (если ничего не задано)

### Commit ID (порядок приоритета)

1. `runs[].results[].properties.commit_id` (per-result)
2. `runs[].versionControlProvenance[].revisionId`
3. `runs[].properties.commit_id` (per-run)
4. HTTP header `X-Commit-Id`
5. Form field `commit_id`
6. Query param `?commit_id=`

## Hard-лимиты безопасности

| Что                                     | Лимит                  | Зачем                 |
| --------------------------------------- | ---------------------- | --------------------- |
| `runs[]` на отчёт                       | 100                    | Защита от bomb-файлов |
| `results[]` на run                      | 100 000                | Память                |
| `locations[]` на result                 | 1 000                  | DoS-protection        |
| `codeFlows[].threadFlows[].locations[]` | 10 000 шагов           | DoS                   |
| Длина строки                            | 1 MiB                  | Memory                |
| Глубина JSON                            | 64                     | Stack overflow        |
| Размер файла                            | ~100 MB (nginx-config) | Транспорт             |

При превышении — Hub возвращает `413` или `422` с описанием.

## Пример загрузки

### Bash + curl

```bash
TOKEN="sa_1a2b3c4d_..."
PRODUCT_ID="abc-123-..."
COMMIT=$(git rev-parse --short HEAD)

curl -X POST "https://hub.example.com/api/v1/products/$PRODUCT_ID/reports" \
  -H "X-API-Key: $TOKEN" \
  -H "X-Commit-Id: $COMMIT" \
  -F "file=@scan.sarif" \
  -F "verify_fixes=true"
```

Ответ:

```json
{
  "data": {
    "report_id": "rpt-uuid",
    "engine": "gosec",
    "results_total": 47,
    "findings_new": 3,
    "findings_updated": 5,
    "findings_closed": 2
  }
}
```

### GitLab CI пример

```yaml
sast:
  stage: test
  image: securego/gosec:latest
  script:
    - gosec -fmt=sarif -out=gosec.sarif ./... || true
    - |
      curl -X POST "$HUB_URL/api/v1/products/$HUB_PRODUCT_ID/reports" \
        -H "X-API-Key: $HUB_API_KEY" \
        -H "X-Commit-Id: $CI_COMMIT_SHA" \
        -F "file=@gosec.sarif"
  artifacts:
    paths: [gosec.sarif]
  variables:
    HUB_URL: https://hub.example.com
    HUB_PRODUCT_ID: <product-uuid>
    # HUB_API_KEY — в CI/CD variables, masked + protected
```

### GitHub Actions пример

```yaml
- name: Upload SARIF to Hub
  if: always()
  run: |
    curl -X POST "${{ secrets.HUB_URL }}/api/v1/products/${{ secrets.HUB_PRODUCT_ID }}/reports" \
      -H "X-API-Key: ${{ secrets.HUB_API_KEY }}" \
      -H "X-Commit-Id: ${{ github.sha }}" \
      -F "file=@gosec.sarif"
```

## Поддерживаемые сканеры (проверены)

- **gosec** — Go security
- **semgrep** — multi-language SAST
- **kics** — IaC misconfigurations
- **trivy** — container/dependency CVE
- **nuclei** — vulnerability templates
- **checkov** — IaC
- **bandit** — Python
- **gitleaks** — secrets
- **kingfisher** — secrets
- **OWASP ZAP** — DAST
- **Burp** (через export-плагин SARIF)
- **DomainScope** — внутренний (см. [`12-domainscope-overview.md`](12-domainscope-overview.md))

## Ротация API keys

API keys имеют срок жизни. Когда подходит к концу:

1. Создать новый key с тем же permission scope
2. Обновить в CI variables
3. Подождать 1-2 CI-прогона
4. Старый key — `Revoke` в UI Hub

Hub продолжит принимать оба ключа до момента, когда вы их отзовете.

## Audit log

Все SARIF-загрузки логируются:

```sql
SELECT created_at, actor_type, payload->>'product_id', payload->>'engine'
FROM audit_logs
WHERE action = 'report.created'
ORDER BY created_at DESC LIMIT 20;
```

## Типовые проблемы

| Симптом                                   | Что проверить                                                                                       |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `401 Unauthorized`                        | API key неверный / истёк / отозван                                                                  |
| `403 Forbidden`                           | SA не имеет permission на этот product                                                              |
| `413 Payload Too Large`                   | Уменьшить SARIF (меньше runs/results) или поднять nginx `client_max_body_size`                      |
| `422 Unprocessable Entity`                | Превышен hard-лимит. См. логи — будет указано какой именно                                          |
| Findings не дедуплицируются между сканами | Проверьте, что `rule_id` и `location` стабильны между запусками сканера                             |
| Severity всегда INFO                      | Сканер не выставляет `level`/`properties.severity` — добавьте поле в SARIF на стороне сканера         |

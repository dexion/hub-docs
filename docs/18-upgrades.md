# 18. Обновления и версионирование

## Формат версий

Hub использует единую схему для всех компонентов:

```
X.Y.BUILD+COMMIT
```

Пример: `0.9.20260602093200+a1b2c3d`

| Часть    | Что                                                  |
| -------- | ---------------------------------------------------- |
| `X.Y`    | Major.Minor — общий для всех компонентов             |
| `BUILD`  | UTC timestamp `YYYYMMDDHHMMSS` (когда собрали)       |
| `COMMIT` | Короткий git-hash (для аудита со стороны поставщика) |

DomainScope версионируется независимо.

## Где смотреть текущую версию

```bash
# UI Hub — footer показывает версии frontend + backend; warning при рассинхроне X.Y

# Backend HTTP
curl https://hub.example.com/version
curl https://hub.example.com/api/v1/version
```

Ответ `/version`:

```json
{
  "version": "0.9.20260602093200+a1b2c3d",
  "commit": "a1b2c3d",
  "built_at": "20260602093200"
}
```

## Стратегия обновления

Hub-образы публикуются с тегом `:latest`. Обновление состоит из двух шагов:

1. `docker compose pull` (или `kubectl rollout restart` в k8s) — подтягивает новый `:latest`
2. Pods пересоздаются, миграции БД накатываются автоматически при старте backend

> Тэг `:latest` указывает на последнюю стабильную версию. Поставщик обновляет его при выходе нового релиза. Если хотите зафиксировать конкретный билд — попросите у поставщика образ с явным тегом и подмените в `docker-compose.yml` / `values.yaml`.

## Перед обновлением (всегда)

1. **Backup БД** (см. [`17-operations.md`](17-operations.md))
2. **Прочитайте release notes** от поставщика — особенно breaking changes
3. **Проверьте env vars** — новые переменные могут требовать значений
4. **Запасной план**: rollback образа на предыдущий тэг

## Docker Compose

```bash
cd /opt/hub
docker compose pull
docker compose up -d

# Проверка
curl https://hub.example.com/version
```

Backend стартует, прокатывает миграции, потом обслуживает.

## Kubernetes (Helm)

```bash
# Если получили обновлённый чарт — переустановить
helm upgrade hub /opt/hub-charts/hub-platform -n hub -f values.yaml

# Если обновился только образ (:latest) — рестарт deployment
kubectl -n hub rollout restart deploy/hub-security-scan-hub-backend
kubectl -n hub rollout restart deploy/hub-security-scan-hub-worker
kubectl -n hub rollout restart deploy/hub-security-scan-hub-frontend
```

Pods пересоздаются rolling-update'ом. Backend подтянет `:latest`, прокатит миграции, потом worker.

> **Важно для k8s + `:latest`**: pod не перетянет новый образ без рестарта (k8s кэширует image manifest). Используйте `imagePullPolicy: Always` в values, либо явный `rollout restart`.

## Миграции БД

Hub использует встроенную систему миграций — backend накатывает изменения схемы автоматически при старте.

### Когда применяются

- При старте backend
- Применяется только то, чего нет в `goose_db_version`

### Что важно знать

- **Прямые миграции** — backend стартует, обновляет схему, потом начинает обслуживать
- **Обратной совместимости миграций нет** — нельзя откатить схему на старую версию без рестора БД
- **Длительные миграции** — release notes от поставщика отмечают ETA для тяжёлых миграций
- **Блокирующие** — backend не отвечает на запросы пока миграция идёт

### Если миграция упала

```bash
# Compose
docker compose logs backend | grep -i goose

# K8s
kubectl -n hub logs deploy/hub-security-scan-hub-backend | grep -i goose

# Состояние
docker compose exec postgres psql -U securityhub securityhub -c \
  "SELECT * FROM goose_db_version ORDER BY version_id DESC LIMIT 5;"
```

Если миграция упала — обычно goose откатывает транзакцию. Перезапустите backend. Если повторно падает — соберите логи и обратитесь к поставщику. **Не правьте схему руками.**

## Rollback

### Compose

```bash
# Остановить
docker compose down

# Восстановить БД из бэкапа (если миграции уже прокатились)
gunzip -c /backup/hub-pre-upgrade.sql.gz | docker compose exec -T postgres psql -U securityhub securityhub

# Откатиться на предыдущий образ (попросите у поставщика конкретный тэг)
# В .env: HUB_IMAGE_TAG=0.9.PREVIOUS
docker compose up -d
```

### Kubernetes

```bash
# Helm revision history
helm history hub -n hub

# Откат на предыдущую ревизию
helm rollback hub <revision> -n hub

# Если БД продвинулась — restore + redeploy
kubectl -n hub scale deploy --all --replicas=0
# restore from PV snapshot / pgdump
helm rollback hub <revision> -n hub
kubectl -n hub scale deploy --all --replicas=2
```

## DomainScope обновление

DomainScope обновляется независимо от Hub:

```bash
cd /opt/domainscope
docker compose pull
docker compose up -d
```

Совместимость API между Hub и DomainScope: оба сервиса используют публичные REST endpoints Hub (`/api/v1/products/<id>/reports` и `/api/v1/projects/<id>/scope/proposals`). При major-bump поставщик отмечает в release notes изменения контракта, если они есть.

## Frontend и backend совместимость

Hub-frontend завязан на minor-версию backend. В footer UI отображается:

```
v0.9.20260602+a1b (frontend)  /  v0.9.20260601+x9y (backend)
```

При расхождении minor — warning в UI. При major — приложение может вести себя некорректно.

В compose/k8s они обновляются вместе (один тэг `:latest`).

## Расписание обновлений

| Окружение           | Частота                                |
| ------------------- | -------------------------------------- |
| Staging / dev       | каждый минор                           |
| Pilot prod          | каждый минор +1 неделя после release   |
| Production stable   | каждый второй минор, или security-only |
| Closed environments | quarterly review + security patches    |

Hot-fix (security CVE) — катите ASAP в любом окружении.

## Major-upgrade (X → X+1)

Major-upgrades содержат breaking changes. Перед накаткой:

1. **Прочитайте migration guide** от поставщика
2. **Тестируйте на staging** — полный цикл upload SARIF, Jira sync, notifications
3. **Запланируйте maintenance window** (минимум 1 час)
4. **Подготовьте rollback-план** (БД snapshot)
5. **Уведомите пользователей** — за 24 часа

Major-upgrade обычно требует:

- Обновить env vars (новые / переименованные)
- Перенастроить интеграции (если поменялся формат конфига)
- Сначала остановить worker, потом обновить backend, потом запустить worker

## Связанные документы

- [`17-operations.md`](17-operations.md) — backup перед обновлением
- [`19-troubleshooting.md`](19-troubleshooting.md) — если что-то пошло не так

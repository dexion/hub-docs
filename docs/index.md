# Security Hub — Administrator Guide

Руководство для администраторов по развёртыванию, настройке и эксплуатации Security Hub и сопутствующего сервиса DomainScope.

Поставка — готовые Docker-образы (тег `:latest`) + Compose-файл / Helm-чарт. Сборка из исходников не предполагается.

Гайд написан для DevOps/SRE/SecOps, которые впервые разворачивают платформу либо поддерживают существующий стенд.

## Структура

### Введение

- [01. Обзор архитектуры](01-overview.md) — компоненты Hub + DomainScope, как они связаны, поток данных
- [02. Системные требования](02-prerequisites.md) — железо, ОС, сеть, домены, сертификаты

### Развёртывание

- [03. Docker Compose](03-deploy-compose.md) — самый быстрый способ, рекомендуется для пилотов и небольших инсталляций
- [04. Kubernetes / Helm](04-deploy-kubernetes.md) — продакшен через umbrella-чарт `hub-platform` (опц. ArgoCD + Vault)

### Конфигурация

- [05. Справочник переменных окружения](05-configuration.md) — полная таблица env vars Hub

### Интеграции

- [06. Keycloak / SSO](06-integration-keycloak.md) — OIDC realm, client, role-mapping, transparent SSO
- [07. Jira](07-integration-jira.md) — полная и частичная автоматизация, reverse-sync, auto-verify
- [08. Mattermost и Telegram](08-integration-notifications.md) — уведомления, ретраи, event-типы
- [09. NetBox](09-integration-netbox.md) — sync периметра, ссылки на NetBox в UI
- [10. LLM + Sandbox](10-integration-llm-sandbox.md) — AI-триаж, sandbox executor (docker/k8s)
- [11. SARIF upload (внешние сканеры)](11-integration-sarif.md) — service accounts, API keys, лимиты

### DomainScope

- [12. Обзор DomainScope](12-domainscope-overview.md) — назначение и связь с Hub
- [13. Установка DomainScope](13-domainscope-install.md) — Docker Compose, Kubernetes
- [14. Управление сканерами](14-domainscope-scanners.md) — subfinder, nmap, nuclei, OpenVAS, TLSX, OWASP ZAP
- [15. NetBox sync в DomainScope](15-domainscope-netbox.md) — импорт/экспорт IP и DNS-зон
- [16. Discovery trails](16-domainscope-trails.md) — происхождение записей, отладка false positives

### Операции

- [17. Эксплуатация](17-operations.md) — бэкапы, мониторинг, логи, метрики
- [18. Обновления и версионирование](18-upgrades.md) — pull `:latest`, миграции, rollback
- [19. Troubleshooting](19-troubleshooting.md) — типовые сбои и как их чинить

## Соглашения

- **`<placeholder>`** — заполните реальным значением (URL, токен, домен)
- **Production** — все рекомендации, относящиеся к боевому стенду, помечены явно
- **WARNING** — действия, которые могут привести к недоступности сервиса или потере данных
- Все образы Hub поставляются с тегом `:latest` — обновление через `docker compose pull` либо `kubectl rollout restart`

## API документация

В каждом развёрнутом инстансе Hub доступна интерактивная Swagger UI:

```
https://<your-hub-domain>/swagger/index.html
```

Используйте для отладки интеграций, проверки контрактов API и тестовых вызовов.

## Docker Hub образы

| Компонент             | Образ                              |
| --------------------- | ---------------------------------- |
| Hub backend           | `dexionius/sshub-backend:latest`   |
| Hub worker            | `dexionius/sshub-worker:latest`    |
| Hub frontend          | `dexionius/sshub-frontend:latest`  |
| DomainScope           | `dexionius/domain-scope:latest`    |

Тег `:latest` указывает на последнюю стабильную версию. Обновление — `docker compose pull` / `kubectl rollout restart`.

## Поддержка

Запросы на доступ к артефактам поставки, новым тегам образов, исправлениям и расширению функциональности — через канал поддержки поставщика.

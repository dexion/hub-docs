# Быстрый старт на k3s (этот репозиторий)

Репозиторий с документацией включает **готовые Helm-чарты** всех компонентов и
**интерактивный установщик** — от голой Linux-VM до рабочего Security Hub за
~10 минут.

## Что в репозитории

| Путь | Назначение |
|------|-----------|
| [`charts/`](https://github.com/dexion/hub-docs/tree/main/charts) | Helm-чарты: `security-scan-hub`, `domainscope`, `openvas`, `owasp-zap`, `netbox`, `hub-platform` (umbrella), `sshub-atlassian-secrets-scanner` |
| [`install.sh`](https://github.com/dexion/hub-docs/blob/main/install.sh) | Интерактивный установщик на k3s (Traefik ingress, cert-manager, случайные пароли в Secrets) |
| [`QUICKSTART.md`](https://github.com/dexion/hub-docs/blob/main/QUICKSTART.md) | Полная пошаговая инструкция (пути Evaluation / Production) |

## Установка

```bash
git clone https://github.com/dexion/hub-docs.git
cd hub-docs
./install.sh
```

По итогу: k3s + Traefik + cert-manager, Hub UI (`https://hub.<domain>`), OpenVAS
Web UI, DomainScope + ZAP, автоматически сшитые с Hub. Все пароли —
сгенерированы и сохранены в Kubernetes Secrets.

## Два пути

| Путь | Когда | Ноды |
|------|-------|------|
| **Evaluation** | Демо / dev / air-gapped | 1 (Hub) |
| **Production** | Сканирование внешнего периметра | 2 (Hub + WireGuard-VPS) |

Production-путь прогоняет egress сканеров через WireGuard на отдельной VPS —
чтобы сканировать свой периметр «снаружи». Детали, требования к железу и сети —
в [QUICKSTART.md](https://github.com/dexion/hub-docs/blob/main/QUICKSTART.md).

## Фиксация версии

Образы `dexionius/*` публикуются с версионными тегами. Чтобы запинить версию
вместо плавающего `:latest`, задайте в values чарта:

```yaml
image:
  tag: "0.24"
```

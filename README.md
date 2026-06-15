# Security Hub

**Security Hub** — платформа управления уязвимостями со встроенными сканерами
(DomainScope, OpenVAS, OWASP ZAP) поверх Kubernetes/k3s.

Этот репозиторий — единая точка для развёртывания и эксплуатации:

- 📖 **Документация** — руководство администратора (развёртывание, настройка,
  интеграции, эксплуатация). Опубликована как сайт:
  **https://dexion.github.io/hub-docs/**
- ⎈ **Helm-чарты** — готовые чарты всех компонентов в [`charts/`](charts/).
- 🚀 **Установщик** — [`install.sh`](install.sh) + [быстрый старт](QUICKSTART.md):
  от голой VM до рабочего Hub за ~10 минут.

## Быстрый старт

```bash
git clone https://github.com/dexion/hub-docs.git
cd hub-docs
./install.sh        # интерактивная установка на k3s
```

Подробно — [QUICKSTART.md](QUICKSTART.md) (пути Evaluation / Production, требования,
WireGuard для сканирования периметра «снаружи»).

## Состав

| Каталог | Назначение |
|---------|-----------|
| [`docs/`](docs/) | Исходники документации (MkDocs Material), публикуются на GitHub Pages |
| [`charts/`](charts/) | Helm-чарты: `security-scan-hub`, `domainscope`, `openvas`, `owasp-zap`, `netbox`, `hub-platform` (umbrella), `sshub-atlassian-secrets-scanner` |
| [`scripts/`](scripts/) | Вспомогательные скрипты (WireGuard setup и пр.) |
| [`install.sh`](install.sh) | Интерактивный установщик на k3s |

## Образы

Все компоненты поставляются готовыми образами `dexionius/*` (Docker Hub) с тегом
`:latest` и версионными тегами (напр. `:0.24`). Версию можно зафиксировать в
values чарта (`image.tag: "0.24"`).

## Документация локально

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
mkdocs serve            # http://127.0.0.1:8000
```

## Лицензия и поддержка

По вопросам развёртывания и коммерческой поддержки — см. контакты в документации.

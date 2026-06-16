# Security Hub — Administrator Guide

Исходники документации Security Hub и DomainScope. Публикуются как сайт через
[MkDocs Material](https://squidfunk.github.io/mkdocs-material/) на GitHub Pages.

**📖 Опубликованный сайт:** https://dexion.github.io/hub-docs/

## Содержание

Контент — в `docs/` (чистый CommonMark, по нумерованным разделам). Структура
навигации задаётся в [`mkdocs.yml`](mkdocs.yml) (`nav:`). Точка входа —
[`docs/index.md`](docs/index.md).

## Локальный предпросмотр

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
mkdocs serve            # http://127.0.0.1:8000 с hot-reload
```

Проверить сборку как в CI (падает на битых ссылках/nav):

```bash
mkdocs build --strict
```

## Публикация

Пуш в `main` → GitHub Actions ([`.github/workflows/docs.yml`](.github/workflows/docs.yml))
собирает `mkdocs build --strict` и деплоит на Pages. Ручного шага нет.

> Включить один раз: **Settings → Pages → Source = GitHub Actions**.

## Принцип переносимости

Исходники держим чистым CommonMark — без Material-специфики в теле страниц
(admonition-блоки `!!! `, content-tabs `=== `, includes `--8<--`). Это значит,
что при необходимости переезд на другой генератор (Docusaurus и т.п.) сводится
к замене `mkdocs.yml` на конфиг нового движка, а сами `.md` остаются как есть.

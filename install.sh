#!/usr/bin/env bash
# install.sh — голая Linux-машина → полностью развёрнутый Security Hub одной командой.
#
# Что делает (идемпотентно — можно перезапускать сколько угодно):
#   1. Ставит k3s (если ещё не стоит) с --disable traefik|без него — зависит от --ingress.
#   2. Ставит helm (если ещё нет).
#   3. Ставит ingress controller (traefik идёт с k3s; nginx — через helm если --ingress nginx).
#   4. Ставит cert-manager.
#   5. helm install hub charts/hub-platform с выбранными TLS / domain / WG.
#
# Использование:
#   sudo ./install.sh                                        # все дефолты
#   sudo ./install.sh --domain mycorp.io --tls letsencrypt --le-email me@x.io
#   sudo ./install.sh --ingress nginx --tls selfsigned
#   sudo ./install.sh --wg-values ./wg-values.yaml           # WG egress
#
# Через env-vars (как альтернатива флагам):
#   DOMAIN, TLS_MODE, LE_EMAIL, INGRESS_CLASS, RELEASE, NAMESPACE, WG_VALUES

set -euo pipefail

# Дефолты
DOMAIN="${DOMAIN:-hub.example.com}"
TLS_MODE="${TLS_MODE:-selfsigned}"            # selfsigned | letsencrypt | existing | disabled
LE_EMAIL="${LE_EMAIL:-admin@example.com}"
INGRESS_CLASS="${INGRESS_CLASS:-traefik}"     # traefik | nginx
RELEASE="${RELEASE:-hub}"
NAMESPACE="${NAMESPACE:-hub}"
WG_VALUES="${WG_VALUES:-}"
SKIP_K3S="${SKIP_K3S:-0}"
SKIP_CERT_MANAGER="${SKIP_CERT_MANAGER:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)        DOMAIN="$2"; shift 2 ;;
    --tls)           TLS_MODE="$2"; shift 2 ;;
    --le-email)      LE_EMAIL="$2"; shift 2 ;;
    --ingress)       INGRESS_CLASS="$2"; shift 2 ;;
    --release)       RELEASE="$2"; shift 2 ;;
    --namespace|-n)  NAMESPACE="$2"; shift 2 ;;
    --wg-values)     WG_VALUES="$2"; shift 2 ;;
    --skip-k3s)      SKIP_K3S=1; shift ;;
    --skip-cert-manager) SKIP_CERT_MANAGER=1; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0"; exit 0 ;;
    *)
      echo "Неизвестный аргумент: $1" >&2; exit 1 ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "Запустите от root (скрипт пишет в /etc/rancher и /usr/local/bin)." >&2
  exit 1
fi

log() { printf "\n\033[1;32m==> %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m!! %s\033[0m\n" "$*"; }

# Не даём зарегистрировать LE-аккаунт на дефолтный email (заглушка)
if [[ "$TLS_MODE" == "letsencrypt" && "$LE_EMAIL" == "admin@example.com" ]]; then
  echo "FATAL: --tls letsencrypt требует --le-email <реальный-адрес>." >&2
  echo "       admin@example.com — placeholder, привяжет LE-аккаунт к чужому ящику." >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# 1. k3s
# -----------------------------------------------------------------------------
if [[ "$SKIP_K3S" -eq 0 ]]; then
  if ! command -v k3s >/dev/null; then
    log "Устанавливаю k3s (ingress=${INGRESS_CLASS})..."
    K3S_DISABLE=""
    if [[ "$INGRESS_CLASS" == "nginx" ]]; then
      K3S_DISABLE="--disable traefik"
    fi
    curl -sfL https://get.k3s.io | sh -s - $K3S_DISABLE --write-kubeconfig-mode 644
  else
    log "k3s уже установлен — пропускаю инсталлер."
  fi
fi

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

# Ждём готовность k3s API
log "Жду k3s API..."
for i in {1..60}; do
  if kubectl get nodes >/dev/null 2>&1; then break; fi
  sleep 2
done
kubectl get nodes

# -----------------------------------------------------------------------------
# 2. helm
# -----------------------------------------------------------------------------
if ! command -v helm >/dev/null; then
  log "Устанавливаю helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
helm version --short

# -----------------------------------------------------------------------------
# 3. Ingress controller (nginx — только если выбран; traefik уже идёт с k3s)
# -----------------------------------------------------------------------------
if [[ "$INGRESS_CLASS" == "nginx" ]]; then
  log "Устанавливаю ingress-nginx..."
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
  helm repo update >/dev/null
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx --create-namespace \
    --set controller.service.type=NodePort \
    --set controller.service.nodePorts.http=80 \
    --set controller.service.nodePorts.https=443
fi

# -----------------------------------------------------------------------------
# 4. cert-manager
# -----------------------------------------------------------------------------
if [[ "$SKIP_CERT_MANAGER" -eq 0 && "$TLS_MODE" != "disabled" && "$TLS_MODE" != "existing" ]]; then
  log "Устанавливаю cert-manager..."
  helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
  helm repo update >/dev/null
  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager --create-namespace \
    --set installCRDs=true \
    --wait --timeout=5m
fi

# -----------------------------------------------------------------------------
# 5. hub-platform
# -----------------------------------------------------------------------------
log "Собираю зависимости umbrella-чарта..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
helm dependency update "${SCRIPT_DIR}/charts/hub-platform"

log "Устанавливаю hub-platform (release=${RELEASE}, ns=${NAMESPACE})..."
HELM_ARGS=(
  upgrade --install "${RELEASE}" "${SCRIPT_DIR}/charts/hub-platform"
  --namespace "${NAMESPACE}" --create-namespace
  --set "global.domain=${DOMAIN}"
  --set "domain=${DOMAIN}"
  --set "ingress.className=${INGRESS_CLASS}"
  --set "tls.mode=${TLS_MODE}"
  --set "tls.letsencryptEmail=${LE_EMAIL}"
  --set "hub.ingress.className=${INGRESS_CLASS}"
  --set "openvas.ingress.className=${INGRESS_CLASS}"
  --set "zap.ingress.className=${INGRESS_CLASS}"
  --set "hub.tls.mode=${TLS_MODE}"
  --set "openvas.tls.mode=${TLS_MODE}"
  --set "zap.tls.mode=${TLS_MODE}"
)

if [[ -n "$WG_VALUES" && -f "$WG_VALUES" ]]; then
  log "Подключаю WireGuard egress из ${WG_VALUES}..."
  HELM_ARGS+=(
    -f "$WG_VALUES"
    --set "wireguard.enabled=true"
    --set "domainscope.wireguard.enabled=true"
    --set "openvas.wireguard.enabled=true"
    --set "zap.wireguard.enabled=true"
  )
fi

helm "${HELM_ARGS[@]}"

# -----------------------------------------------------------------------------
# Готово — печатаем дружественный summary с креденшалами
# -----------------------------------------------------------------------------
log "Готово. Состояние подов:"
kubectl -n "${NAMESPACE}" get pods -l "app.kubernetes.io/instance=${RELEASE}" -o wide || true

# Достаём сгенерированные секреты (если они уже есть в кластере)
HUB_ADMIN_PWD=$(kubectl -n "${NAMESPACE}" get secret "${RELEASE}-hub-secrets" -o jsonpath='{.data.localAdminPassword}' 2>/dev/null | base64 -d 2>/dev/null || echo "<not-yet-generated>")
HUB_DB_PWD=$(kubectl -n "${NAMESPACE}" get secret "${RELEASE}-hub-secrets" -o jsonpath='{.data.dbPassword}' 2>/dev/null | base64 -d 2>/dev/null || echo "<not-yet>")
OPENVAS_PWD=$(kubectl -n "${NAMESPACE}" get secret "${RELEASE}-openvas-secrets" -o jsonpath='{.data.adminPassword}' 2>/dev/null | base64 -d 2>/dev/null || echo "<not-yet>")
ZAP_KEY=$(kubectl -n "${NAMESPACE}" get secret "${RELEASE}-zap-secrets" -o jsonpath='{.data.apiKey}' 2>/dev/null | base64 -d 2>/dev/null || echo "<not-yet>")
SA_TOKEN=$(kubectl -n "${NAMESPACE}" get secret "${RELEASE}-hub-secrets" -o jsonpath='{.data.defaultSAKeyPlain}' 2>/dev/null | base64 -d 2>/dev/null || echo "<not-yet>")

SCHEME="http"
[ "$TLS_MODE" != "disabled" ] && SCHEME="https"

# ANSI цвета (используем $'...' чтобы escape-коды интерпретировались тут же,
# а не оставались литералами в heredoc-выводе).
B=$'\033[1m'; G=$'\033[1;32m'; Y=$'\033[1;33m'; R=$'\033[1;31m'; C=$'\033[1;36m'; N=$'\033[0m'

cat <<EOF

╔═══════════════════════════════════════════════════════════════════════╗
║                     Security Hub готов к работе                       ║
╚═══════════════════════════════════════════════════════════════════════╝

${G}▶ Hub Web UI${N}     →  ${C}${SCHEME}://${DOMAIN}/${N}
   Логин:   ${B}admin@localhost.local${N}
   Пароль:  ${B}${HUB_ADMIN_PWD}${N}

${G}▶ OpenVAS UI${N}     →  ${C}${SCHEME}://openvas.${DOMAIN}/${N}
   Логин:   ${B}admin${N}
   Пароль:  ${B}${OPENVAS_PWD}${N}

${G}▶ Service Tokens${N}
   Hub default SA token:   ${B}${SA_TOKEN}${N}
   ZAP API key:            ${B}${ZAP_KEY}${N}
   Hub Postgres password:  ${B}${HUB_DB_PWD}${N}

${R}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}
${R}⚠  ВНИМАНИЕ${N}: пароли и токены сгенерированы случайно при первой
   установке и сохранены в ${B}${RELEASE}-*-secrets${N} (k8s Secrets).
   Смените пароль admin@localhost.local в Hub UI ${B}СРАЗУ${N}.
${R}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}

${Y}⏳  OpenVAS feed init${N} занимает ~10–30 минут (~5 GB). До завершения
    OpenVAS-сканы не найдут уязвимостей. Прогресс:
      kubectl -n ${NAMESPACE} get pod -l app.kubernetes.io/component=openvas
      kubectl -n ${NAMESPACE} describe pod -l app.kubernetes.io/component=openvas | grep -A1 'Init Container'

${Y}⏳  Default project${N}: автосоздан проект «${B}$(kubectl -n "${NAMESPACE}" get secret "${RELEASE}-hub-secrets" -o jsonpath='{.data.defaultProjectId}' 2>/dev/null | base64 -d 2>/dev/null || echo Default)${N}»
    с начальным scope, который можно поменять в hub UI или через helm:
      helm upgrade ${RELEASE} <chart> --reuse-values --set global.defaultProject.scope=foo.com,bar.com

${G}Полезные команды${N}
  kubectl -n ${NAMESPACE} get pods                       # состояние всех компонентов
  kubectl -n ${NAMESPACE} logs deploy/${RELEASE}-backend  # логи бэкенда
  kubectl -n ${NAMESPACE} logs deploy/${RELEASE}-domainscope-domainscope -c domainscope

EOF

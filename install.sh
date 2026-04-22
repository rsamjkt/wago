#!/usr/bin/env bash
set -eo pipefail

# ─────────────────────────────────────────────
#  Arunika-WA — Linux Install Script
#  Usage: curl -fsSL https://raw.githubusercontent.com/rsamjkt/wago/main/install.sh | bash
# ─────────────────────────────────────────────

REPO_URL="https://github.com/rsamjkt/wago.git"
INSTALL_DIR="/opt/arunika-wa"
IMAGE="rsamjkt/arunika-wa:latest"
COMPOSE_FILE="docker-compose.yml"

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLU='\033[0;34m'
BLD='\033[1m'
RST='\033[0m'

info()    { echo -e "${BLU}[•]${RST} $*"; }
success() { echo -e "${GRN}[✓]${RST} $*"; }
warn()    { echo -e "${YLW}[!]${RST} $*"; }
error()   { echo -e "${RED}[✗]${RST} $*"; exit 1; }
ask()     { echo -ne "${BLD}[?]${RST} $* "; }

# Baca input dari terminal langsung meski dijalankan via curl | bash
tty_read() {
  local var="$1"
  local default="${2:-}"
  local val=""
  read -r val </dev/tty || true
  if [[ -z "$val" && -n "$default" ]]; then
    val="$default"
  fi
  printf -v "$var" '%s' "$val"
}

tty_read_secret() {
  local var="$1"
  local val=""
  stty -echo </dev/tty
  read -r val </dev/tty || true
  stty echo </dev/tty
  echo ""
  printf -v "$var" '%s' "$val"
}

echo -e "
${BLD}${YLW}╔═══════════════════════════════════════╗
║      Arunika-WA  ·  WhatsApp API      ║
║         Installer for Linux           ║
╚═══════════════════════════════════════╝${RST}
"

# ── Root check ───────────────────────────────
if [[ $EUID -ne 0 ]]; then
  error "Jalankan sebagai root: sudo bash install.sh"
fi

# ── Detect package manager ───────────────────
if command -v apt-get &>/dev/null; then
  PKG_MGR="apt"
elif command -v dnf &>/dev/null; then
  PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
  PKG_MGR="yum"
else
  error "Package manager tidak dikenali (butuh apt / dnf / yum)"
fi

# ── Install dependencies ─────────────────────
install_pkg() {
  case "$PKG_MGR" in
    apt) apt-get install -y -qq "$@" ;;
    dnf) dnf install -y -q "$@" ;;
    yum) yum install -y -q "$@" ;;
  esac
}

info "Mengecek dependensi..."

for cmd in curl git; do
  if ! command -v "$cmd" &>/dev/null; then
    info "Menginstal $cmd..."
    if [[ "$PKG_MGR" == "apt" ]]; then
      apt-get update -qq
    fi
    install_pkg "$cmd"
  fi
done

# ── Install Docker ───────────────────────────
if ! command -v docker &>/dev/null; then
  info "Menginstal Docker..."
  curl -fsSL https://get.docker.com | bash
  systemctl enable --now docker
  success "Docker terinstal"
else
  success "Docker sudah ada: $(docker --version | cut -d' ' -f3 | tr -d ',')"
fi

# ── Docker Compose (plugin) ──────────────────
if ! docker compose version &>/dev/null 2>&1; then
  info "Menginstal Docker Compose plugin..."
  COMPOSE_VER=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4)
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  ARCH_SLUG="x86_64" ;;
    aarch64) ARCH_SLUG="aarch64" ;;
    *)       error "Arsitektur tidak didukung: $ARCH" ;;
  esac
  mkdir -p /usr/local/lib/docker/cli-plugins
  curl -fsSL "https://github.com/docker/compose/releases/download/${COMPOSE_VER}/docker-compose-linux-${ARCH_SLUG}" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  success "Docker Compose ${COMPOSE_VER} terinstal"
else
  success "Docker Compose sudah ada: $(docker compose version --short)"
fi

# ── Clone / update repo ──────────────────────
ENV_BACKUP=""
if [[ -f "$INSTALL_DIR/src/.env" ]]; then
  ENV_BACKUP=$(mktemp)
  cp "$INSTALL_DIR/src/.env" "$ENV_BACKUP"
  info "Konfigurasi .env di-backup"
fi

if [[ -d "$INSTALL_DIR" ]]; then
  info "Memperbarui Arunika-WA..."
  rm -rf "$INSTALL_DIR"
fi
info "Mengunduh Arunika-WA ke $INSTALL_DIR..."
git clone --quiet "$REPO_URL" "$INSTALL_DIR"

if [[ -n "$ENV_BACKUP" ]]; then
  cp "$ENV_BACKUP" "$INSTALL_DIR/src/.env"
  rm -f "$ENV_BACKUP"
  success "Konfigurasi .env dipulihkan"
fi
success "Source siap di $INSTALL_DIR"

cd "$INSTALL_DIR"

# ── Setup .env ───────────────────────────────
if [[ ! -f src/.env ]]; then
  cp src/.env.example src/.env
  info "File src/.env dibuat dari template"
fi

echo ""
echo -e "${BLD}━━━  Konfigurasi Arunika-WA  ━━━${RST}"
echo ""

# PORT
ask "Port aplikasi [default: 3000]:"
tty_read PORT "3000"

# AUTH
echo ""
warn "Basic Auth digunakan untuk melindungi API."
ask "Username login [default: admin]:"
tty_read AUTH_USER "admin"

ask "Password login (kosong = auto-generate):"
tty_read_secret AUTH_PASS
if [[ -z "$AUTH_PASS" ]]; then
  AUTH_PASS=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
  warn "Password digenerate otomatis: ${BLD}${AUTH_PASS}${RST}"
fi

# WEBHOOK (opsional)
echo ""
ask "URL Webhook (Enter untuk skip):"
tty_read WEBHOOK_URL ""

# ── Tulis .env ───────────────────────────────
cat > src/.env <<ENVEOF
# ──────────────────────────────────────
#  Arunika-WA — konfigurasi
#  Generated: $(date '+%Y-%m-%d %H:%M:%S')
# ──────────────────────────────────────

APP_PORT=${PORT}
APP_HOST=0.0.0.0
APP_DEBUG=false
APP_OS=Chrome
APP_BASIC_AUTH=${AUTH_USER}:${AUTH_PASS}
APP_BASE_PATH=
APP_TRUSTED_PROXIES=0.0.0.0/0

DB_URI=file:storages/whatsapp.db?_foreign_keys=on
DB_KEYS_URI=file::memory:?cache=shared&_foreign_keys=on

WHATSAPP_AUTO_REPLY=
WHATSAPP_AUTO_MARK_READ=false
WHATSAPP_AUTO_REJECT_CALL=false
WHATSAPP_AUTO_DOWNLOAD_MEDIA=true
WHATSAPP_WEBHOOK=${WEBHOOK_URL}
WHATSAPP_WEBHOOK_SECRET=
WHATSAPP_WEBHOOK_INSECURE_SKIP_VERIFY=false
WHATSAPP_WEBHOOK_EVENTS=message,message.reaction,message.revoked,message.edited,message.ack,message.deleted,group.participants
WHATSAPP_WEBHOOK_INCLUDE_OUTGOING=false
WHATSAPP_ACCOUNT_VALIDATION=true
WHATSAPP_PRESENCE_ON_CONNECT=unavailable
WHATSAPP_CHAT_STORAGE=true

CHATWOOT_ENABLED=false
CHATWOOT_URL=
CHATWOOT_API_TOKEN=
CHATWOOT_ACCOUNT_ID=
CHATWOOT_INBOX_ID=
CHATWOOT_DEVICE_ID=
CHATWOOT_IMPORT_MESSAGES=false
CHATWOOT_DAYS_LIMIT_IMPORT_MESSAGES=3
ENVEOF

# ── Update port di docker-compose.yml ────────
sed -i "s|\"3000:3000\"|\"${PORT}:3000\"|g" docker-compose.yml

# ── Buat direktori runtime ───────────────────
mkdir -p storages statics/qrcode statics/senditems statics/media
chown -R 20001:20000 storages statics 2>/dev/null || true
success "Direktori runtime siap"

# ── Tarik image & jalankan ───────────────────
echo ""
info "Menarik Docker image (${IMAGE})..."

BUILD_FLAG=""
if docker pull "$IMAGE" 2>/dev/null; then
  success "Image berhasil diunduh dari Docker Hub"
else
  warn "Image tidak tersedia di registry — build dari source..."
  COMPOSE_FILE="docker-compose.build.yml"
  BUILD_FLAG="--build"
fi

info "Menjalankan Arunika-WA..."
docker compose -f "$COMPOSE_FILE" up -d $BUILD_FLAG

# ── Selesai ──────────────────────────────────
IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")

echo ""
echo -e "${GRN}${BLD}╔═══════════════════════════════════════╗
║       Arunika-WA siap digunakan!      ║
╚═══════════════════════════════════════╝${RST}
"
echo -e "  ${BLD}URL${RST}       : http://${IP}:${PORT}"
echo -e "  ${BLD}Username${RST}  : ${AUTH_USER}"
echo -e "  ${BLD}Password${RST}  : ${AUTH_PASS}"
echo -e "  ${BLD}Data${RST}      : ${INSTALL_DIR}/storages"
echo ""
echo -e "  Perintah berguna:"
echo -e "  ${BLU}cd ${INSTALL_DIR} && docker compose -f ${COMPOSE_FILE} logs -f${RST}    — lihat log"
echo -e "  ${BLU}cd ${INSTALL_DIR} && docker compose -f ${COMPOSE_FILE} restart${RST}     — restart"
echo -e "  ${BLU}cd ${INSTALL_DIR} && docker compose -f ${COMPOSE_FILE} down${RST}        — stop"
echo ""
echo -e "  Scan QR Code di browser untuk mulai menggunakan WhatsApp."
echo ""

#!/usr/bin/env bash
set -eo pipefail

# ─────────────────────────────────────────────
#  Arunika-WA — Linux Install Script (Binary)
#  Tanpa Docker, langsung build & jalankan
#  Usage: curl -fsSL https://raw.githubusercontent.com/rsamjkt/wago/main/install-binary.sh | bash
# ─────────────────────────────────────────────

REPO_URL="https://github.com/rsamjkt/wago.git"
INSTALL_DIR="/opt/arunika-wa"
BINARY="$INSTALL_DIR/arunika-wa"
SERVICE_NAME="arunika-wa"
GO_VERSION="1.25.4"
GO_MIN_MINOR=25

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

tty_read() {
  local var="$1" default="${2:-}" val=""
  read -r val </dev/tty || true
  [[ -z "$val" && -n "$default" ]] && val="$default"
  printf -v "$var" '%s' "$val"
}

tty_read_secret() {
  local var="$1" val=""
  stty -echo </dev/tty
  read -r val </dev/tty || true
  stty echo </dev/tty
  echo ""
  printf -v "$var" '%s' "$val"
}

echo -e "
${BLD}${YLW}╔═══════════════════════════════════════╗
║      Arunika-WA  ·  WhatsApp API      ║
║      Installer Binary (tanpa Docker)  ║
╚═══════════════════════════════════════╝${RST}
"

# ── Root check ───────────────────────────────
if [[ $EUID -ne 0 ]]; then
  error "Jalankan sebagai root: sudo bash install-binary.sh"
fi

# ── Detect distro ────────────────────────────
if command -v apt-get &>/dev/null; then
  PKG_MGR="apt"
elif command -v dnf &>/dev/null; then
  PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
  PKG_MGR="yum"
else
  error "Package manager tidak dikenali (butuh apt / dnf / yum)"
fi

install_pkg() {
  case "$PKG_MGR" in
    apt) apt-get install -y -qq "$@" ;;
    dnf) dnf install -y -q "$@" ;;
    yum) yum install -y -q "$@" ;;
  esac
}

# ── Paket sistem ─────────────────────────────
info "Menginstal paket sistem..."
if [[ "$PKG_MGR" == "apt" ]]; then
  apt-get update -qq
  install_pkg git curl wget gcc ffmpeg libwebp-dev ca-certificates
elif [[ "$PKG_MGR" == "dnf" ]]; then
  dnf install -y -q git curl wget gcc ffmpeg libwebp ca-certificates
else
  yum install -y -q git curl wget gcc ffmpeg libwebp ca-certificates
fi
success "Paket sistem siap"

# ── Install / update Go ───────────────────────
need_go=false
if command -v go &>/dev/null; then
  CURRENT_MINOR=$(go version | grep -oP 'go1\.\K[0-9]+' | head -1)
  if [[ "${CURRENT_MINOR:-0}" -lt "$GO_MIN_MINOR" ]]; then
    warn "Go $(go version | awk '{print $3}') terlalu lama — butuh 1.${GO_MIN_MINOR}+"
    need_go=true
  else
    success "Go sudah ada: $(go version | awk '{print $3}')"
  fi
else
  need_go=true
fi

if [[ "$need_go" == true ]]; then
  info "Menginstal Go ${GO_VERSION}..."
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  GO_ARCH="amd64" ;;
    aarch64) GO_ARCH="arm64" ;;
    armv7l)  GO_ARCH="armv6l" ;;
    *)       error "Arsitektur tidak didukung: $ARCH" ;;
  esac
  GO_TAR="go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
  curl -fsSL "https://go.dev/dl/${GO_TAR}" -o "/tmp/${GO_TAR}"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "/tmp/${GO_TAR}"
  rm -f "/tmp/${GO_TAR}"
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  success "Go ${GO_VERSION} terinstal"
fi

export PATH="$PATH:/usr/local/go/bin"

# ── Clone / update repo ───────────────────────
# Backup .env jika sudah ada dari install sebelumnya
ENV_BACKUP=""
if [[ -f "$INSTALL_DIR/src/.env" ]]; then
  ENV_BACKUP=$(mktemp)
  cp "$INSTALL_DIR/src/.env" "$ENV_BACKUP"
  info "Konfigurasi .env di-backup"
fi

# Hapus dan clone ulang — paling aman, hindari konflik git
if [[ -d "$INSTALL_DIR" ]]; then
  info "Memperbarui Arunika-WA..."
  rm -rf "$INSTALL_DIR"
fi
info "Mengunduh Arunika-WA ke $INSTALL_DIR..."
git clone --quiet "$REPO_URL" "$INSTALL_DIR"

# Pulihkan .env
if [[ -n "$ENV_BACKUP" ]]; then
  cp "$ENV_BACKUP" "$INSTALL_DIR/src/.env"
  rm -f "$ENV_BACKUP"
  success "Konfigurasi .env dipulihkan"
fi
success "Source siap di $INSTALL_DIR"

# ── Build binary ──────────────────────────────
info "Build binary (ini beberapa menit pertama kali)..."
cd "$INSTALL_DIR/src"
CGO_ENABLED=1 go build -ldflags="-w -s" -o "$BINARY" .
success "Binary siap: $BINARY"

# ── Setup .env ───────────────────────────────
if [[ ! -f "$INSTALL_DIR/src/.env" ]]; then
  cp "$INSTALL_DIR/src/.env.example" "$INSTALL_DIR/src/.env"
fi

echo ""
echo -e "${BLD}━━━  Konfigurasi Arunika-WA  ━━━${RST}"
echo ""

ask "Port aplikasi [default: 3000]:"
tty_read PORT "3000"

echo ""
warn "Basic Auth melindungi akses ke API."
ask "Username login [default: admin]:"
tty_read AUTH_USER "admin"

ask "Password login (kosong = auto-generate):"
tty_read_secret AUTH_PASS
if [[ -z "$AUTH_PASS" ]]; then
  AUTH_PASS=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
  warn "Password digenerate otomatis: ${BLD}${AUTH_PASS}${RST}"
fi

echo ""
ask "URL Webhook (Enter untuk skip):"
tty_read WEBHOOK_URL ""

# ── Tulis .env ───────────────────────────────
cat > "$INSTALL_DIR/src/.env" <<ENVEOF
APP_PORT=${PORT}
APP_HOST=0.0.0.0
APP_DEBUG=false
APP_OS=Chrome
APP_BASIC_AUTH=${AUTH_USER}:${AUTH_PASS}
APP_BASE_PATH=
APP_TRUSTED_PROXIES=0.0.0.0/0

DB_URI=file:${INSTALL_DIR}/storages/whatsapp.db?_foreign_keys=on
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

# ── Direktori runtime ─────────────────────────
mkdir -p "$INSTALL_DIR/storages" \
         "$INSTALL_DIR/statics/qrcode" \
         "$INSTALL_DIR/statics/senditems" \
         "$INSTALL_DIR/statics/media"

# ── User sistem ───────────────────────────────
if ! id arunika &>/dev/null; then
  useradd -r -s /sbin/nologin -d "$INSTALL_DIR" arunika
fi
chown -R arunika:arunika "$INSTALL_DIR"
success "Direktori & user runtime siap"

# ── systemd service ───────────────────────────
info "Membuat systemd service..."
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<SVCEOF
[Unit]
Description=Arunika-WA WhatsApp API Gateway
After=network.target

[Service]
Type=simple
User=arunika
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${INSTALL_DIR}/src/.env
ExecStart=${BINARY} rest
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=arunika-wa

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"
success "Service arunika-wa aktif"

# ── Selesai ───────────────────────────────────
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
echo -e "  ${BLU}journalctl -u arunika-wa -f${RST}              — lihat log"
echo -e "  ${BLU}systemctl restart arunika-wa${RST}             — restart"
echo -e "  ${BLU}systemctl stop arunika-wa${RST}                — stop"
echo -e "  ${BLU}nano ${INSTALL_DIR}/src/.env${RST}   — edit konfigurasi"
echo ""
echo -e "  Update ke versi terbaru:"
echo -e "  ${BLU}curl -fsSL https://raw.githubusercontent.com/rsamjkt/wago/main/install-binary.sh | sudo bash${RST}"
echo ""
echo -e "  Scan QR Code di browser untuk mulai menggunakan WhatsApp."
echo ""

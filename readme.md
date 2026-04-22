<div align="center">
  <img src="src/views/assets/arunika.svg" alt="Arunika-WA" width="160" height="160">

# Arunika-WA

**WhatsApp API Gateway — siap pakai, multi-device, ringan**

[![Release](https://img.shields.io/github/v/release/rsamjkt/wago?color=F97316&label=versi)](https://github.com/rsamjkt/wago/releases/latest)
[![Docker](https://img.shields.io/badge/Docker-rsamjkt%2Farunika--wa-0ea5e9?logo=docker)](https://hub.docker.com/r/rsamjkt/arunika-wa)
[![License](https://img.shields.io/badge/Lisensi-MIT-22c55e)](LICENSE)
[![Go](https://img.shields.io/badge/Go-1.25-00ADD8?logo=go)](https://go.dev)

</div>

---

## Apa ini?

Arunika-WA adalah server API WhatsApp berbasis Go yang bisa dijalankan sendiri (*self-hosted*). Hubungkan WhatsApp Anda lewat QR Code, lalu kirim/terima pesan, media, dan event melalui REST API atau MCP.

Cocok untuk:
- Bot WhatsApp otomatis
- Integrasi notifikasi sistem
- CRM & customer support
- Automasi pesan bisnis

---

## Fitur Utama

- **Multi-device** — kelola banyak akun WhatsApp dalam satu server
- **REST API** — lengkap dengan dokumentasi UI berbasis web
- **MCP Server** — integrasi dengan AI agent (Claude, dll)
- **Webhook** — terima event real-time (pesan masuk, reaksi, status, dll)
- **Kirim semua jenis media** — teks, gambar, video, audio, dokumen, sticker, lokasi
- **Manajemen grup** — buat, kelola anggota, kirim pesan grup
- **Chat storage** — riwayat pesan tersimpan di SQLite / PostgreSQL
- **Integrasi Chatwoot** — sinkronisasi dua arah dengan CRM Chatwoot
- **Multi-arch Docker** — AMD64 & ARM64

---

## Deploy Cepat (Linux)

Satu perintah, langsung jalan:

```bash
curl -fsSL https://raw.githubusercontent.com/rsamjkt/wago/main/install.sh | sudo bash
```

Script otomatis menginstal Docker, mengunduh Arunika-WA, dan menanyakan konfigurasi dasar (port, username, password).

---

## Docker Manual

```bash
# Pull image
docker pull rsamjkt/arunika-wa:latest

# Jalankan
docker run -d \
  --name arunika-wa \
  --restart on-failure \
  -p 3000:3000 \
  -e APP_BASIC_AUTH=admin:password \
  -v $(pwd)/storages:/app/storages \
  -v $(pwd)/statics:/app/statics \
  rsamjkt/arunika-wa:latest
```

Atau dengan `docker compose`:

```bash
git clone https://github.com/rsamjkt/wago.git
cd wago
cp src/.env.example src/.env
# Edit src/.env sesuai kebutuhan
docker compose up -d
```

Buka browser: `http://localhost:3000`

---

## Build dari Source

```bash
git clone https://github.com/rsamjkt/wago.git
cd wago/src

# Jalankan langsung
go run . rest

# Atau build binary
go build -o arunika-wa .
./arunika-wa rest
```

**Kebutuhan:** Go 1.25+, FFmpeg (untuk media), GCC (untuk SQLite CGO)

---

## Konfigurasi

Salin dan edit file `.env`:

```bash
cp src/.env.example src/.env
```

| Variable | Default | Keterangan |
|----------|---------|-----------|
| `APP_PORT` | `3000` | Port server |
| `APP_BASIC_AUTH` | — | Format: `user:pass` atau `user1:pass1,user2:pass2` |
| `APP_DEBUG` | `false` | Mode debug |
| `DB_URI` | SQLite | Ganti ke PostgreSQL dengan `postgres://...` |
| `WHATSAPP_WEBHOOK` | — | URL tujuan event (bisa lebih dari satu, pisah koma) |
| `WHATSAPP_WEBHOOK_EVENTS` | semua | Filter event: `message,message.reaction,...` |
| `WHATSAPP_AUTO_DOWNLOAD_MEDIA` | `true` | Auto unduh media masuk |
| `WHATSAPP_AUTO_MARK_READ` | `false` | Auto tandai pesan sebagai terbaca |
| `WHATSAPP_AUTO_REJECT_CALL` | `false` | Auto tolak panggilan masuk |
| `CHATWOOT_ENABLED` | `false` | Aktifkan integrasi Chatwoot |

---

## REST API

Setelah server jalan, buka `http://localhost:3000` untuk UI lengkap.

Ringkasan endpoint utama:

| Method | Endpoint | Fungsi |
|--------|----------|--------|
| `GET` | `/app/devices` | Daftar device terhubung |
| `POST` | `/app/login` | Login via QR / Pairing Code |
| `DELETE` | `/app/logout` | Logout device |
| `POST` | `/send/message` | Kirim pesan teks |
| `POST` | `/send/image` | Kirim gambar |
| `POST` | `/send/video` | Kirim video |
| `POST` | `/send/audio` | Kirim audio |
| `POST` | `/send/file` | Kirim dokumen |
| `POST` | `/send/location` | Kirim lokasi |
| `POST` | `/send/sticker` | Kirim sticker |
| `GET` | `/user/info` | Info akun WhatsApp |
| `GET` | `/chat/list` | Daftar chat |
| `GET` | `/chat/messages` | Riwayat pesan |
| `GET` | `/group/list` | Daftar grup |
| `POST` | `/group/create` | Buat grup baru |

Semua endpoint device-scoped membutuhkan header `X-Device-Id` atau query param `device_id`.

---

## WebSocket Events

Webhook dikirim ke URL yang dikonfigurasi di `WHATSAPP_WEBHOOK` sebagai POST request JSON.

| Event | Keterangan |
|-------|-----------|
| `message` | Pesan masuk |
| `message.reaction` | Reaksi pada pesan |
| `message.revoked` | Pesan dihapus oleh pengirim |
| `message.edited` | Pesan diedit |
| `message.ack` | Status terkirim/dibaca |
| `message.deleted` | Pesan dihapus |
| `group.participants` | Perubahan anggota grup |

---

## Struktur Proyek

```
src/
├── main.go                 # Entry point
├── cmd/                    # CLI: rest, mcp subcommand
├── config/                 # Konfigurasi (Viper)
├── domains/                # Interface & DTO
├── usecase/                # Business logic
├── infrastructure/
│   ├── whatsapp/           # Protokol WhatsApp (whatsmeow)
│   ├── chatstorage/        # Persistensi SQLite/PostgreSQL
│   └── chatwoot/           # Integrasi Chatwoot
├── ui/
│   ├── rest/               # HTTP handler (Fiber)
│   └── mcp/                # MCP server handler
├── views/                  # UI web (Vue.js 3)
└── pkg/                    # Helper & utilitas
```

---

## MCP Server

Untuk integrasi dengan AI agent (seperti Claude):

```bash
./arunika-wa mcp
# Server jalan di localhost:8080
```

---

## Lisensi

MIT — © 2024 rsamjkt

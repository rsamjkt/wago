#!/bin/sh
set -e

# Fix ownership of mounted volumes at startup (requires root entry point)
for d in /app/storages /app/statics /app/statics/qrcode /app/statics/senditems /app/statics/media; do
	[ -d "$d" ] || mkdir -p "$d"
	chown -R arunika:arunika "$d" 2>/dev/null || true
done

exec su-exec arunika /app/arunika-wa "$@"

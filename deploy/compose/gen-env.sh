#!/usr/bin/env bash
#
# gen-env.sh — generate deploy/compose/.env from .env.example.
#
# Auto-fills the stable infrastructure/identity SECRETS with fresh random
# values (openssl). Leaves the two things the script can't know — your relay
# owner pubkey and your domain — as CHANGE_ME placeholders unless you pass
# them in, so `./run.sh` still refuses to boot a half-configured relay.
#
# Secrets never touch git: .env is gitignored, and this script prints nothing
# secret to stdout. Run it ON the deploy VM.
#
# Usage:
#   ./gen-env.sh [--domain chat.example.com] [--owner <64-hex-pubkey>] [--force]
#
#   --domain  fill BUZZ_DOMAIN/RELAY_URL/media/CORS from one hostname
#   --owner   fill RELAY_OWNER_PUBKEY (your Nostr pubkey, 64 hex chars)
#   --force   overwrite an existing .env (ROTATES secrets — can orphan data)
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

DOMAIN="" OWNER="" FORCE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="${2:?--domain needs a hostname}"; shift 2 ;;
    --owner)  OWNER="${2:?--owner needs a 64-hex pubkey}"; shift 2 ;;
    --force)  FORCE=true; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v openssl >/dev/null || { echo "openssl is required" >&2; exit 1; }
[[ -f .env.example ]] || { echo "run me from deploy/compose (no .env.example here)" >&2; exit 1; }

if [[ -f .env && "$FORCE" != true ]]; then
  echo "refusing to overwrite existing .env — use --force to regenerate." >&2
  echo "(regenerating ROTATES every secret and can orphan your existing data.)" >&2
  exit 1
fi

cp .env.example .env

# Rewrite a single KEY=... line in-place (value is treated literally).
set_kv() {
  awk -v k="$1" -v v="$2" '
    BEGIN { FS="="; done=0 }
    $1==k && !done { print k"="v; done=1; next }
    { print }
  ' .env > .env.tmp && mv .env.tmp .env
}

# 1) Stable secrets — 64 hex chars each, generated locally, never displayed.
for var in BUZZ_RELAY_PRIVATE_KEY BUZZ_GIT_HOOK_HMAC_SECRET \
           POSTGRES_PASSWORD REDIS_PASSWORD TYPESENSE_API_KEY \
           BUZZ_S3_ACCESS_KEY BUZZ_S3_SECRET_KEY; do
  set_kv "$var" "$(openssl rand -hex 32)"
done

# 2) "Just chat" relay toggles (mirror the desktop strip-down).
set_kv BUZZ_HUDDLE_AUDIO_AVAILABLE false
set_kv BUZZ_SERVE_GIT_WEB_GUI false

# Desktop-app webview origins. The Tauri app is NOT served from your domain —
# its webview origin is `tauri://localhost` (macOS/Linux) or
# `http://tauri.localhost` (Windows). Omit these and the relay returns no
# `access-control-allow-origin` header, so every desktop client fails to connect
# with the unhelpful message "Community rejected: Load failed". This applies to
# the official upstream build too, not just our own — see
# `crates/buzz-relay/src/config.rs` (the documented example lists `tauri://localhost`).
DESKTOP_ORIGINS="tauri://localhost,http://tauri.localhost"

# 3) Identity + domain — filled if provided, else forced to CHANGE_ME.
set_kv RELAY_OWNER_PUBKEY "${OWNER:-CHANGE_ME_OWNER_PUBKEY_HEX}"
if [[ -n "$DOMAIN" ]]; then
  set_kv BUZZ_DOMAIN "$DOMAIN"
  set_kv RELAY_URL "wss://$DOMAIN"
  set_kv BUZZ_MEDIA_BASE_URL "https://$DOMAIN/media"
  set_kv BUZZ_MEDIA_SERVER_DOMAIN "$DOMAIN"
  set_kv BUZZ_CORS_ORIGINS "https://$DOMAIN,$DESKTOP_ORIGINS"
else
  set_kv BUZZ_DOMAIN "CHANGE_ME_your_domain"
  set_kv RELAY_URL "wss://CHANGE_ME_your_domain"
  set_kv BUZZ_MEDIA_BASE_URL "https://CHANGE_ME_your_domain/media"
  set_kv BUZZ_MEDIA_SERVER_DOMAIN "CHANGE_ME_your_domain"
  set_kv BUZZ_CORS_ORIGINS "https://CHANGE_ME_your_domain,$DESKTOP_ORIGINS"
fi

chmod 600 .env

# Match the same shape run.sh guards on: KEY=...CHANGE_ME (ignore comments).
placeholder_re='^[A-Za-z_][A-Za-z0-9_]*=.*CHANGE_ME'
echo "Wrote deploy/compose/.env (mode 600) with generated secrets."
remaining="$(grep -cE "$placeholder_re" .env || true)"
if [[ "$remaining" -gt 0 ]]; then
  echo
  echo "Still to set by hand ($remaining placeholder line(s) remain):"
  grep -nE "$placeholder_re" .env | sed 's/^/  /'
  echo
  echo "  --owner  = your Nostr pubkey (64 hex) — makes you relay admin"
  echo "  --domain = the hostname whose DNS A-record points at this VM"
  echo "Re-run with those flags, or edit .env directly."
else
  echo "No placeholders left. Next: BUZZ_COMPOSE_TLS=true ./run.sh start"
fi

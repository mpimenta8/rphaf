#!/usr/bin/env bash
#
# backup.sh — nightly backup for the rphaf/Buzz compose stack.
#
# Captures a consistent snapshot of everything you can't recreate:
#   - Postgres        (logical `pg_dump` — the critical, irreplaceable state)
#   - MinIO media      (object volume tar — uploaded images/video/attachments)
#   - git-data volume  (repos, if the git feature is ever used)
#   - .env             (your stable secrets — keep this backup dir locked down)
# Then rotates local copies and, if configured, ships the set OFFSITE.
#
# A backup that lives only on the same VM does NOT survive a VM/disk loss —
# set an offsite target (see below) before you rely on this.
#
# Run from deploy/compose. Configure via env or an optional ./backup.env:
#   BACKUP_DIR            where to write locally      (default /var/backups/buzz)
#   KEEP_DAYS             LOCAL retention in days     (default 14)
#   BACKUP_RCLONE_REMOTE  rclone remote:path offsite  (default empty = local only)
#   BACKUP_ALERT_CMD      command run on failure      (default empty = no alerting)
#                         Invoked as: $BACKUP_ALERT_CMD "<message>"
#                         QUOTE THE WHOLE VALUE in backup.env, or the shell reads
#                         `BACKUP_ALERT_CMD=aws sns publish …` as an assignment
#                         prefix and tries to run `sns` instead of setting the var.
#                         NO ARGUMENT MAY CONTAIN SPACES: expansion below is
#                         deliberately unquoted so the command word-splits, and
#                         quotes inside the value are not re-parsed as quotes.
#                         Need a spaced argument? Point this at a wrapper script.
#
# KEEP_DAYS prunes only the LOCAL copies. Nothing here ever deletes anything
# offsite — that is deliberate, so a compromised relay host cannot destroy
# backup history. Set offsite retention with a bucket lifecycle rule instead
# (see PROVISIONING.md §6a).
#
# Cron example (nightly 03:15 UTC):
#   15 3 * * * cd /opt/rphaf/deploy/compose && ./backup.sh >> /var/log/buzz-backup.log 2>&1
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# Optional local config file (keep secrets/paths out of the crontab line).
[[ -f backup.env ]] && . ./backup.env

BACKUP_DIR="${BACKUP_DIR:-/var/backups/buzz}"
KEEP_DAYS="${KEEP_DAYS:-14}"
RCLONE_REMOTE="${BACKUP_RCLONE_REMOTE:-}"
ALERT_CMD="${BACKUP_ALERT_CMD:-}"
COMPOSE=(docker compose --env-file .env -f compose.yml)

log() { printf '[buzz-backup %s] %s\n' "$(date -u +%H:%M:%SZ)" "$*"; }

# REPORTED doubles as "this run's failure has already been announced", so `die`
# and the EXIT trap can't both alert (or both log) for the same failure.
REPORTED=0
alert() {
  local out
  [[ "$REPORTED" -eq 1 ]] && return 0
  REPORTED=1
  [[ -n "$ALERT_CMD" ]] || return 0
  # Unquoted on purpose: ALERT_CMD is a command line, not a single word.
  # shellcheck disable=SC2086
  if ! out="$($ALERT_CMD "rphaf backup FAILED on $(hostname -s): $1" 2>&1)"; then
    log "WARNING: BACKUP_ALERT_CMD itself failed — this failure went unreported: ${out}"
  fi
}

die() { log "ERROR: $*" >&2; alert "$*"; exit 1; }

# Catch anything `set -e` aborts on that didn't route through `die`. A backup
# job that dies quietly is worse than no backup — you find out at restore time.
on_exit() {
  local rc=$?
  [[ "$rc" -eq 0 ]] && return 0
  [[ "$REPORTED" -eq 1 ]] && return 0   # die() already said what went wrong
  log "ERROR: aborted unexpectedly (exit ${rc})"
  alert "aborted unexpectedly (exit ${rc})"
}
trap on_exit EXIT

[[ -f .env ]] || die "no .env here — run from deploy/compose on the deploy host"
command -v docker >/dev/null || die "docker not found"
"${COMPOSE[@]}" ps --status running --services 2>/dev/null | grep -qx postgres \
  || die "postgres service is not running — start the stack first (./run.sh start)"

TS="$(date -u +%Y%m%d-%H%M%SZ)"
DEST="${BACKUP_DIR}/${TS}"
mkdir -p "$DEST"
chmod 700 "$BACKUP_DIR" "$DEST"

# --- 1. Postgres: logical dump (transactionally consistent), gzipped. -------
log "dumping postgres…"
"${COMPOSE[@]}" exec -T postgres sh -c \
  'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --clean --if-exists' \
  | gzip -9 > "${DEST}/postgres.sql.gz"
[[ -s "${DEST}/postgres.sql.gz" ]] || die "postgres dump is empty — aborting"

# --- 2. Volume tars (media + git) from a throwaway alpine container. --------
tar_volume() {
  local pattern="$1" out="$2" vol rc=0
  vol="$(docker volume ls --format '{{.Name}}' | grep -E "$pattern" | head -1 || true)"
  if [[ -z "$vol" ]]; then
    log "  WARNING: no volume matching /$pattern/ — ${out} NOT backed up"
    return
  fi
  log "archiving volume ${vol} -> ${out}…"
  docker run --rm -v "${vol}:/data:ro" -v "${DEST}:/backup" alpine \
    tar czf "/backup/${out}" -C /data . || rc=$?
  # tar: 0 = clean, 1 = files changed underneath us (expected on a live volume,
  # archive is still usable), 2+ = genuinely broken. Only the last is fatal.
  case "$rc" in
    0) ;;
    1) log "  WARNING: files changed while archiving ${vol} — archive kept, may be slightly inconsistent" ;;
    *) die "failed to archive volume ${vol} (tar exit ${rc}) — refusing to report a partial backup as success" ;;
  esac
}
tar_volume 'buzz.*minio-data$' minio-data.tar.gz
tar_volume 'buzz.*git-data$'   git-data.tar.gz

# --- 3. Secrets snapshot (locked down). ------------------------------------
cp .env "${DEST}/env.snapshot"
chmod 600 "${DEST}/env.snapshot"

# --- 4. Manifest + checksums. ----------------------------------------------
( cd "$DEST" && sha256sum ./* > SHA256SUMS )
log "local backup ready: ${DEST} ($(du -sh "$DEST" | cut -f1))"

# --- 5. Offsite (optional, strongly recommended). --------------------------
if [[ -n "$RCLONE_REMOTE" ]]; then
  command -v rclone >/dev/null || die "BACKUP_RCLONE_REMOTE set but rclone not installed"

  # Tier the upload so retention can differ by age (PROVISIONING.md §6a):
  #   daily/   kept 30 days  — the routine "restore last night" case
  #   monthly/ kept 1 year   — the long tail, for damage noticed months later
  # The FIRST successful backup of each calendar month becomes that month's
  # monthly. Deliberately not "if today is the 1st": a single failed run on the
  # 1st would otherwise cost the whole month's long-term restore point.
  TIER=daily
  if ! rclone lsf "${RCLONE_REMOTE}/monthly/" 2>/dev/null | grep -q "^$(date -u +%Y%m)"; then
    TIER=monthly
    log "no monthly backup yet for $(date -u +%Y-%m) — filing this run as monthly"
  fi

  log "shipping offsite -> ${RCLONE_REMOTE}/${TIER}/${TS}"
  rclone copy "$DEST" "${RCLONE_REMOTE}/${TIER}/${TS}"
  log "offsite copy complete"
else
  log "WARNING: no offsite target (BACKUP_RCLONE_REMOTE empty)."
  log "         A local-only backup dies with the VM — configure offsite."
fi

# --- 6. Rotate LOCAL copies only. ------------------------------------------
# Offsite retention is a bucket lifecycle rule (PROVISIONING.md §6a) — this
# script has no delete permission offsite and must not gain one.
log "pruning local backups older than ${KEEP_DAYS} day(s)…"
find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -mtime "+${KEEP_DAYS}" -exec rm -rf {} +

# --- 7. Success marker. -----------------------------------------------------
# Alerting covers a run that fails; it cannot cover a run that never happened
# (broken crontab, stopped VM). Check this file's age to catch that.
date -u +%Y-%m-%dT%H:%M:%SZ > "${BACKUP_DIR}/LAST_SUCCESS"
log "done."

#!/usr/bin/env bash
#
# backup.sh - Full-system backup of both SSDs to the 4TB drive.
#
# Scheduling (cron, see dotfiles/crontab): cron fires daily at 20:00 and
# this script decides whether a run is due: every three months after the
# last successful run (if the machine is off past the due date, the first
# run after it catches up). The cron job runs with SKIP_WINDOWS=1
# (Linux SSD only).
#
# Rotation ("standard procedure", two copies, 1 TB cap):
#   A FRESH backup is written to a staging directory and verified. Only a
#   successful copy overwrites the old one:
#
#       bak.bak (oldest) is deleted, bak -> bak.bak, staging -> bak
#
#   Everything under the backup root (bak + bak.bak + windows/ + logs) may
#   use at most MAX_USAGE (1 TB). While two copies fit within the cap the
#   old one is kept ("don't overwrite if there's space"); when they would
#   exceed the cap, the fresh copy overwrites the old one instead. If
#   anything fails, the old copies are left untouched.
#
# What is backed up:
#   Linux SSD (rotated)      / -> etc boot home srv usr/local var/lib
#   Windows SSD (separate)   -> Users ProgramData tools, kept in windows/
#                             and refreshed only by a manual full run
#
# What is filtered out (only what can be reproduced and is not in a git
# repo, see EXCLUDES): package caches, SDKs, toolchains, build outputs,
# logs, crash dumps, trash, ISOs, /usr, /opt, /var/cache, /var/log, the
# Windows system directories, pagefiles, installed programs and games.
#
# The 4TB drive is NTFS, so the backup is stored as tar archives to keep
# ownership, permissions, symlinks and hardlinks intact for restore.
#
# Usage:
#   backup.sh [--force]     --force runs now, ignoring the schedule
#
# Environment overrides (mainly for testing):
#   BACKUP_ROOT=/path       use this directory instead of mounting the 4TB
#   LINUX_PATHS="..."       override the Linux paths to back up
#   WINDOWS_PATHS="..."     override the Windows paths to back up
#   SKIP_WINDOWS=1          do not back up the Windows SSD (cron default)
#   MAX_USAGE=1T            usage cap for the whole backup root
#   VERIFY=0                skip archive verification

set -Eeuo pipefail

# cron runs with a minimal environment
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ----------------------------------------------------------------- config --
BACKUP_UUID="089667E59667D1AC"   # 4TB NTFS drive (filesystem UUID)
WINDOWS_LABEL="Windows"          # Windows SSD partition label
INTERVAL_MONTHS="${INTERVAL_MONTHS:-3}"   # run every three months
VERIFY="${VERIFY:-1}"
MAX_USAGE="${MAX_USAGE:-1T}"      # the whole backup root may use at most this
MIN_FREE_G="${MIN_FREE_G:-100}"   # refuse to start below this much free space (GB)

LINUX_PATHS="${LINUX_PATHS:-etc boot home srv usr/local var/lib}"
WINDOWS_PATHS="${WINDOWS_PATHS:-Users ProgramData tools}"
SKIP_WINDOWS="${SKIP_WINDOWS:-0}"

# Reproducible and not tracked in a git repo -> not backed up.
EXCLUDES=(
  # Re-downloadable toolchains, SDKs and package caches
  'home/joachim/.cache'
  'home/joachim/.npm'
  'home/joachim/.gradle'
  'home/joachim/.pub-cache'
  'home/joachim/.cargo'
  'home/joachim/go'
  'home/joachim/.docker'
  'home/joachim/.ollama'
  'home/joachim/.lmstudio'
  'home/joachim/.dartServer'
  'home/joachim/android_sdk'
  'home/joachim/iso'
  'home/joachim/.local/share/Trash'
  'home/joachim/.local/share/nvim/mason'
  'home/joachim/.local/share/uv'
  'home/joachim/.local/share/spotify-launcher'
  'home/joachim/.local/share/JetBrains'
  'home/joachim/.local/share/Google'
  'home/joachim/projects/omnetpp/inet-*'
  # Crash dumps, logs and stale backup copies
  'home/joachim/java_error_in_studio*.log'
  'home/joachim/*.hprof'
  'home/joachim/matlab_crash_dump*'
  'home/joachim/.MathWorks.backup.*'
  'home/joachim/.matlab.backup.*'
  # Build outputs at any depth (untracked and reproducible)
  '*/node_modules'
  '*/target'
  '*/dist'
  '*/build'
  '*/out'
  '*/__pycache__'
  '*/venv'
  '*/.venv'
  '*/.dart_tool'
  '*/.gradle'
  '*/.next'
  '*/.turbo'
  '*/.parcel-cache'
  '*/.pytest_cache'
  '*/.mypy_cache'
  '*/.ruff_cache'
)

# ------------------------------------------------------------------ setup --
FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

STATE_DIR="$HOME/.local/state"
mkdir -p "$STATE_DIR"
STAMP="$STATE_DIR/backup.last-success"
LOCK="$STATE_DIR/backup.lock"
LOG="$STATE_DIR/backup.log"

exec 9>"$LOCK"
flock -n 9 || { echo "backup: another run is already in progress" >&2; exit 1; }

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG" >&2; }
die() { log "ERROR: $*"; exit 1; }
human() { numfmt --to=iec "$1"; }

# --------------------------------------------------------------- schedule --
# Due every INTERVAL_MONTHS after the last successful run. If the machine
# is off past the due date, the first run after it catches up.
if [ "$FORCE" -eq 0 ]; then
  last=$(cat "$STAMP" 2>/dev/null) || last="1970-01-01"
  next_due=$(date -d "$last +${INTERVAL_MONTHS} months" +%Y-%m-%d 2>/dev/null) || next_due="1970-01-01"
  today=$(date +%Y-%m-%d)
  if [ "$today" \< "$next_due" ]; then
    log "not due (last success $last, next due $next_due) -> exiting"
    exit 0
  fi
  log "due since $next_due (last success $last) -> running"
else
  log "--force: running now"
fi

# ------------------------------------------------------------------ mounts --
dev_by_uuid()   { lsblk -rno NAME,UUID  | awk -v u="$1" '$2 == u { print "/dev/" $1; exit }'; }
dev_by_label()  { lsblk -rno NAME,LABEL | awk -v l="$1" '$2 == l { print "/dev/" $1; exit }'; }
mountpoint_of() { findmnt -n -o TARGET -S "$1" 2>/dev/null || true; }
is_mounted_ro() { findmnt -n -o OPTIONS -S "$1" 2>/dev/null | grep -qw ro; }

ensure_mounted() { # $1 = device, $2 = ro|rw; prints the mount point
  local dev=$1 want=$2 mnt out
  mnt=$(mountpoint_of "$dev")
  if [ -n "$mnt" ] && [ "$want" = rw ] && is_mounted_ro "$dev"; then
    log "$dev is mounted read-only, remounting read-write"
    udisksctl unmount -b "$dev" >/dev/null
    mnt=""
  fi
  if [ -z "$mnt" ]; then
    if [ "$want" = ro ]; then
      out=$(udisksctl mount -b "$dev" --options ro) || die "cannot mount $dev read-only"
    else
      out=$(udisksctl mount -b "$dev") || die "cannot mount $dev read-write"
    fi
    mnt=${out##* at }
    log "mounted $dev at $mnt"
  fi
  { [ -n "$mnt" ] && [ -d "$mnt" ]; } || die "no mount point for $dev"
  printf '%s\n' "$mnt"
}

if [ -n "${BACKUP_ROOT:-}" ]; then
  BACKUP_ROOT=${BACKUP_ROOT%/}
  mkdir -p "$BACKUP_ROOT"
  log "using BACKUP_ROOT override: $BACKUP_ROOT"
else
  dev=$(dev_by_uuid "$BACKUP_UUID")
  [ -n "$dev" ] || die "4TB drive (UUID $BACKUP_UUID) not found - is it connected?"
  mnt=$(ensure_mounted "$dev" rw) || die "cannot mount the 4TB drive"
  BACKUP_ROOT="$mnt/backup"
  mkdir -p "$BACKUP_ROOT"
fi
LOG="$BACKUP_ROOT/backup.log"   # keep the log on the drive from here on
log "backup root: $BACKUP_ROOT"
log "destination: $(df -h "$BACKUP_ROOT" | tail -1)"
free_g=$(( $(df -B1 --output=avail "$BACKUP_ROOT" | tail -1) / 1073741824 ))
[ "$free_g" -ge "$MIN_FREE_G" ] || die "only ${free_g}G free on the backup drive (need at least ${MIN_FREE_G}G)"
log "free space on the backup drive: ${free_g}G (usage cap: ${MAX_USAGE})"

WIN_MNT=""
if [ "$SKIP_WINDOWS" -eq 1 ]; then
  log "SKIP_WINDOWS=1: Windows SSD not backed up this run"
else
  wdev=$(dev_by_label "$WINDOWS_LABEL")
  bdev=$(dev_by_uuid "$BACKUP_UUID")
  if [ -z "$wdev" ] || [ "$wdev" = "$bdev" ]; then
    die "Windows partition (label '$WINDOWS_LABEL') not found"
  fi
  WIN_MNT=$(ensure_mounted "$wdev" ro) || die "cannot mount the Windows SSD"
fi

# ------------------------------------------------------------------- stage --
BAK="$BACKUP_ROOT/bak"
BAK_BAK="$BACKUP_ROOT/bak.bak"
STAGE="$BACKUP_ROOT/.bak.new"
WIN_DIR="$BACKUP_ROOT/windows"

guarded_rm() { # only ever delete inside BACKUP_ROOT
  case "$1" in
    "$BACKUP_ROOT"/*) rm -rf -- "$1" ;;
    *) die "refusing to delete unexpected path: $1" ;;
  esac
}

on_failure() {
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    log "run failed (rc=$rc): removing staging, previous copies are untouched"
    guarded_rm "$STAGE" || true
    rm -f -- "$WIN_DIR/.windows.tar.new" "$WIN_DIR/.windows.tar.new.warnings" "$WIN_DIR/.info.txt.new" 2>/dev/null || true
  fi
}
trap on_failure EXIT

guarded_rm "$STAGE"
mkdir -p "$STAGE"
log "staging fresh backup in $STAGE"

# --------------------------------------------------------------------- tar --
exclude_args=()
for e in "${EXCLUDES[@]}"; do exclude_args+=(--exclude="$e"); done

SKIPPED=0
META_FLAGS="--numeric-owner --acls --xattrs"

run_tar() { # $1 = archive, $2 = source root, rest = paths
  local archive=$1 src=$2; shift 2
  local warnings="${archive}.warnings"
  local rc=0
  # shellcheck disable=SC2086
  tar $META_FLAGS --ignore-failed-read \
      --checkpoint=100000 --checkpoint-action=echo \
      -C "$src" "${exclude_args[@]}" -cf "$archive" "$@" 2>"$warnings" || rc=$?
  if [ "$rc" -gt 1 ]; then
    log "tar failed for $(basename "$archive") (rc=$rc):"
    tail -20 "$warnings" >&2 || true
    return 1
  fi
  local n
  n=$(grep -c -E 'Permission denied|Cannot open' "$warnings") || n=0
  SKIPPED=$((SKIPPED + n))
  log "$(basename "$archive"): $(du -h "$archive" | cut -f1), skipped-unreadable=$n"
}

# shellcheck disable=SC2086
run_tar "$STAGE/linux.tar" / $LINUX_PATHS

# The Windows SSD backup is kept separately in windows/ (it changes rarely
# and is refreshed only by a manual full run). It is verified and replaced
# atomically, and is not part of the bak/bak.bak rotation.
if [ -n "$WIN_MNT" ]; then
  mkdir -p "$WIN_DIR"
  META_FLAGS="--numeric-owner"   # Windows ACLs/xattrs cannot be preserved from Linux anyway
  # shellcheck disable=SC2086
  run_tar "$WIN_DIR/.windows.tar.new" "$WIN_MNT" $WINDOWS_PATHS
  if [ "$VERIFY" -eq 1 ]; then
    log "verifying windows.tar (reading it back)"
    tar -tf "$WIN_DIR/.windows.tar.new" >/dev/null || die "verification failed for windows.tar"
  fi
  {
    echo "windows backup created : $(date -Is)"
    echo "host                   : $(uname -n)"
    echo "source                 : $WIN_MNT ($WINDOWS_PATHS)"
    echo "note                   : kept separately, refreshed only by a manual full run"
    echo "restore                : extract windows.tar over the Windows partition root"
  } > "$WIN_DIR/.info.txt.new"
  mv -f -- "$WIN_DIR/.windows.tar.new" "$WIN_DIR/windows.tar"
  mv -f -- "$WIN_DIR/.windows.tar.new.warnings" "$WIN_DIR/windows.tar.warnings"
  mv -f -- "$WIN_DIR/.info.txt.new" "$WIN_DIR/info.txt"
  log "windows backup updated: $WIN_DIR/windows.tar ($(human "$(du -sb "$WIN_DIR/windows.tar" | cut -f1)"))"
fi

# ------------------------------------------------------------------ verify --
COUNTS="$STAGE/.counts"
: > "$COUNTS"
if [ "$VERIFY" -eq 1 ]; then
  for t in "$STAGE"/*.tar; do
    log "verifying $(basename "$t") (reading it back)"
    n=$(tar -tf "$t" | wc -l) || die "verification failed for $t"
    printf '%s\t%s\n' "$(basename "$t")" "$n" >> "$COUNTS"
  done
else
  for t in "$STAGE"/*.tar; do
    printf '%s\t?\n' "$(basename "$t")" >> "$COUNTS"
  done
fi

# ---------------------------------------------------------------- manifest --
{
  echo "backup created : $(date -Is)"
  echo "host           : $(uname -n)"
  echo "created by     : dotfiles/scripts/backup.sh"
  echo "linux ssd      : / ($LINUX_PATHS)"
  if [ -n "$WIN_MNT" ]; then echo "windows ssd    : $WIN_MNT ($WINDOWS_PATHS)"; fi
  echo "destination    : $BACKUP_ROOT"
  echo
  echo "contents:"
  while IFS=$'\t' read -r name count; do
    echo "  $name  ($(du -h "$STAGE/$name" | cut -f1), $count files)"
  done < "$COUNTS"
  echo
  if [ -e "$WIN_DIR/windows.tar" ]; then
    echo "windows backup (separate, not rotated): $WIN_DIR/windows.tar ($(du -h "$WIN_DIR/windows.tar" | cut -f1))"
  fi
  echo
  echo "excluded (reproducible + not in a git repo):"
  printf '  %s\n' "${EXCLUDES[@]}"
  echo
  echo "skipped unreadable files (running as user, e.g. /etc/shadow): $SKIPPED"
  echo "per-archive details: the *.warnings files next to the archives"
  echo
  echo "restore linux  : sudo tar --numeric-owner --acls --xattrs -xf bak/linux.tar -C /"
  if [ -e "$WIN_DIR/windows.tar" ]; then
    echo "restore windows: extract $WIN_DIR/windows.tar over the Windows partition root"
  fi
} > "$STAGE/info.txt"
rm -f "$COUNTS"

# ------------------------------------------------------------------ rotate --
# Cap: everything under the backup root (bak + bak.bak + windows/ + logs)
# may use at most MAX_USAGE. Keep two copies while they fit ("don't
# overwrite if there's space"); overwrite the old one when they don't.
sync
size_new=$(du -sb "$STAGE" | cut -f1)
size_cur=0
if [ -e "$BAK" ]; then size_cur=$(du -sb "$BAK" | cut -f1); fi
other=0
if [ -e "$WIN_DIR" ]; then other=$(du -sb "$WIN_DIR" | cut -f1); fi
for f in "$BACKUP_ROOT"/*.log; do
  if [ -e "$f" ]; then other=$((other + $(du -sb "$f" | cut -f1))); fi
done
max_bytes=$(numfmt --from=iec "$MAX_USAGE")

if [ $((size_new + other)) -gt "$max_bytes" ]; then
  die "fresh backup ($(human "$size_new")) plus existing files ($(human "$other")) exceed the ${MAX_USAGE} cap - old copies untouched"
fi

if [ ! -e "$BAK" ]; then
  mv -- "$STAGE" "$BAK"
  log "first backup: $BAK ($(human "$size_new"))"
elif [ $((size_new + size_cur + other)) -le "$max_bytes" ]; then
  log "two copies fit within ${MAX_USAGE}: keeping the old one as bak.bak"
  guarded_rm "$BAK_BAK"
  mv -f -- "$BAK" "$BAK_BAK"
  mv -- "$STAGE" "$BAK"
else
  log "two copies would exceed ${MAX_USAGE}: the fresh copy overwrites the old one"
  guarded_rm "$BAK_BAK"
  guarded_rm "$BAK"
  mv -- "$STAGE" "$BAK"
fi
date -Is > "$STAMP"
log "SUCCESS: fresh backup in $BAK (total usage: $(human $((size_new + size_cur + other))))"
log "log: $LOG"

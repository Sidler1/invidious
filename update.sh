#!/usr/bin/env bash
# Rolling update for a systemd-managed Invidious install.
#
# Layout under INSTALL_DIR (default /var/www/invidious):
#   releases/<id>/          one directory per downloaded release
#   current -> releases/..  symlink the service runs from (switched atomically)
#   config.yml              live configuration, never inside a release
#   invidious.log           log file, never inside a release
#
# One-time migration from the old in-place layout:
#   mv $INSTALL_DIR/config/config.yml $INSTALL_DIR/config.yml
#   the updated invidious.service (paths point at .../current) is installed
#   automatically when running as root (or with INSTALL_UNIT=1)
#
# Database migrations run automatically before switching to the new release
# (set RUN_MIGRATIONS=0 to skip). After starting the new release a health
# check runs; on failure the previous release is restored. Requires: curl,
# tar, sha256sum, gh (for provenance).
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/var/www/invidious}"
SERVICE="${SERVICE:-invidious}"
SERVICE_USER="${SERVICE_USER:-invidious}"
RELEASE_BASE="${RELEASE_BASE:-https://github.com/Sidler1/invidious/releases/download/release-master}"
TARBALL="invidious-x86_64-unknown-linux-gnu.tar.gz"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:3000/api/v1/stats}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-60}"
KEEP_RELEASES="${KEEP_RELEASES:-3}"
REQUIRE_ATTESTATION="${REQUIRE_ATTESTATION:-1}"
GITHUB_REPO="${GITHUB_REPO:-Sidler1/invidious}"
SYSTEMCTL="${SYSTEMCTL:-systemctl}"
RUN_MIGRATIONS="${RUN_MIGRATIONS:-1}"
UNIT_DIR="${UNIT_DIR:-/etc/systemd/system}"
if [ "$(id -u)" = 0 ]; then INSTALL_UNIT="${INSTALL_UNIT:-1}"; else INSTALL_UNIT="${INSTALL_UNIT:-0}"; fi

log() { printf '[update] %s\n' "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

log "Downloading release..."
curl -fsSL -o "$workdir/$TARBALL" "$RELEASE_BASE/$TARBALL"
curl -fsSL -o "$workdir/$TARBALL.sha256" "$RELEASE_BASE/$TARBALL.sha256"

log "Verifying checksum..."
( cd "$workdir" && sha256sum -c --quiet "$TARBALL.sha256" )

if [ "$REQUIRE_ATTESTATION" = "1" ]; then
  command -v gh >/dev/null || die "gh CLI is required to verify build provenance (set REQUIRE_ATTESTATION=0 to skip)"
  log "Verifying build provenance..."
  gh attestation verify "$workdir/$TARBALL" --repo "$GITHUB_REPO"
fi

release_id="$(sha256sum "$workdir/$TARBALL" | cut -c1-16)"
release_dir="$INSTALL_DIR/releases/$release_id"
current_link="$INSTALL_DIR/current"

if [ -d "$release_dir" ] && [ "$(readlink -f "$current_link" 2>/dev/null || true)" = "$release_dir" ]; then
  log "Release $release_id is already installed and active. Nothing to do."
  exit 0
fi

[ -f "$INSTALL_DIR/config.yml" ] || die "Expected live config at $INSTALL_DIR/config.yml (see header of this script)"

log "Extracting release $release_id..."
rm -rf "$release_dir"
mkdir -p "$release_dir"
tar --no-same-owner -xzf "$workdir/$TARBALL" -C "$release_dir"
chmod +x "$release_dir/invidious"
mkdir -p "$release_dir/config"
ln -sfn "$INSTALL_DIR/config.yml" "$release_dir/config/config.yml"
if [ "$(id -u)" = 0 ]; then
  chown -R "$SERVICE_USER:$SERVICE_USER" "$release_dir"
fi

RUN_MIGRATIONS="${RUN_MIGRATIONS:-1}"
if [ "$RUN_MIGRATIONS" = "1" ]; then
  log "Running database migrations..."
  # Non-concurrent CREATE INDEX takes a SHARE lock on the table for its
  # duration; the old release keeps serving reads meanwhile.
  ( cd "$release_dir" && ./invidious --migrate ) || die "Migration failed; nothing was switched."
fi

previous="$(readlink -f "$current_link" 2>/dev/null || true)"

switch_to() {
  ln -sfn "$1" "$current_link.tmp"
  mv -T "$current_link.tmp" "$current_link"
}

healthy() {
  local deadline=$(( $(date +%s) + HEALTH_TIMEOUT ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if curl -fsS -o /dev/null "$HEALTH_URL"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# Prune old releases, keeping the newest KEEP_RELEASES and never the active one.
prune_old_releases() {
  find "$INSTALL_DIR/releases" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' \
    | sort -rn | tail -n +$((KEEP_RELEASES + 1)) | cut -d' ' -f2- \
    | while read -r old; do
        [ "$(readlink -f "$old")" = "$(readlink -f "$current_link")" ] && continue
        log "Pruning $old"
        rm -rf "$old"
      done
}

log "Stopping $SERVICE..."
"$SYSTEMCTL" stop "$SERVICE"
# From here on, any abort must bring the service back up on whatever
# `current` points at. Starting an already-running unit is a no-op, so the
# trap stays installed for the rest of the run.
trap '"$SYSTEMCTL" start "$SERVICE" || true; rm -rf "$workdir"' EXIT
switch_to "$release_dir"

if [ "$INSTALL_UNIT" = "1" ] && [ -f "$release_dir/invidious.service" ]; then
  if ! cmp -s "$release_dir/invidious.service" "$UNIT_DIR/$SERVICE.service"; then
    log "Installing updated $SERVICE.service unit..."
    install -m 644 "$release_dir/invidious.service" "$UNIT_DIR/$SERVICE.service"
    "$SYSTEMCTL" daemon-reload
  fi
fi

log "Starting $SERVICE..."
"$SYSTEMCTL" start "$SERVICE"

if healthy; then
  log "Release $release_id is up and healthy."
else
  log "Health check against $HEALTH_URL failed for release $release_id."
  if [ -n "$previous" ] && [ -d "$previous" ]; then
    log "Rolling back to $previous..."
    "$SYSTEMCTL" stop "$SERVICE"
    switch_to "$previous"
    "$SYSTEMCTL" start "$SERVICE"
    if healthy; then
      log "Rollback succeeded."
    else
      log "Rollback started but the health check is still failing."
    fi
  fi
  die "Update failed."
fi

prune_old_releases || log "Pruning old releases failed (ignored)"

log "Update complete."
"$SYSTEMCTL" status "$SERVICE" --no-pager -n 20 || true

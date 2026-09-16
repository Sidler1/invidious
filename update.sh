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
#   install the updated invidious.service (paths point at .../current)
#   systemctl daemon-reload
#
# After starting the new release a health check runs; on failure the previous
# release is restored. Requires: curl, tar, sha256sum, gh (for provenance).
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

log "Stopping $SERVICE..."
"$SYSTEMCTL" stop "$SERVICE"
switch_to "$release_dir"
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

# Prune old releases, keeping the newest KEEP_RELEASES and never the active one.
find "$INSTALL_DIR/releases" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' \
  | sort -rn | tail -n +$((KEEP_RELEASES + 1)) | cut -d' ' -f2- \
  | while read -r old; do
      [ "$(readlink -f "$old")" = "$(readlink -f "$current_link")" ] && continue
      log "Pruning $old"
      rm -rf "$old"
    done

log "Update complete."
"$SYSTEMCTL" status "$SERVICE" --no-pager -n 20 || true

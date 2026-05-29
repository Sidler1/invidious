#!/usr/bin/env bash
set -euo pipefail

# Install location can be overridden: INSTALL_DIR=/home/invidious/invidious ./update.sh
INSTALL_DIR="${INSTALL_DIR:-/var/www/invidious}"
SERVICE="${SERVICE:-invidious}"
RELEASE_BASE="https://github.com/Sidler1/invidious/releases/download/release-master"
TARBALL="invidious-x86_64-unknown-linux-gnu.tar.gz"

cd "$INSTALL_DIR"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "Downloading release..."
wget -O "$workdir/$TARBALL" "$RELEASE_BASE/$TARBALL"
wget -O "$workdir/$TARBALL.sha256" "$RELEASE_BASE/$TARBALL.sha256"

echo "Verifying checksum..."
# The published .sha256 references the bare filename, so verify from workdir.
( cd "$workdir" && sha256sum -c "$TARBALL.sha256" )

echo "Extracting to staging..."
staging="$workdir/staging"
mkdir -p "$staging"
tar xzf "$workdir/$TARBALL" -C "$staging"

echo "Stopping $SERVICE..."
systemctl stop "$SERVICE"

# From here on, make sure the service is brought back up even if a step fails.
trap 'systemctl start "$SERVICE" || true; rm -rf "$workdir"' EXIT

echo "Installing update..."
# Replace code + bundled assets wholesale so files removed upstream don't
# linger. config/config.yml is never shipped in the tarball, so the running
# configuration is left untouched (only config.example.yml + sql are updated).
rm -rf assets locales
cp -a "$staging"/. "$INSTALL_DIR"/
chmod +x "$INSTALL_DIR/invidious"

echo "Starting $SERVICE..."
systemctl start "$SERVICE"

# Update succeeded; drop the restart-on-failure trap.
trap 'rm -rf "$workdir"' EXIT

echo "Update complete."
journalctl -u "$SERVICE" -n 50 --no-pager

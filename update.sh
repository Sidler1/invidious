#!/usr/bin/env bash
set -euo pipefail

cd /var/www/invidious/

URL="https://github.com/Sidler1/invidious/releases/download/release-master/invidious-x86_64-unknown-linux-gnu.tar.gz"
TARBALL="invidious-x86_64-unknown-linux-gnu.tar.gz"

wget -O "$TARBALL" "$URL"
systemctl stop invidious
tar xzf "$TARBALL"
rm -f "$TARBALL"
systemctl start invidious

journalctl -u invidious -f

#!/usr/bin/env bash
# Exercises update.sh against a fake release and a fake systemctl.
# Usage: scripts/test-update.sh
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

install_dir="$tmp/install"
release_src="$tmp/release"
mkdir -p "$install_dir" "$release_src/dist/config"
echo "hmac_key: test" > "$install_dir/config.yml"

# Fake release: a shell script standing in for the binary.
printf '#!/bin/sh\necho fake-invidious\n' > "$release_src/dist/invidious"
chmod +x "$release_src/dist/invidious"
cp "$here/config/config.example.yml" "$release_src/dist/config/"
tarball="invidious-x86_64-unknown-linux-gnu.tar.gz"
tar -czf "$release_src/$tarball" -C "$release_src/dist" .
( cd "$release_src" && sha256sum "$tarball" > "$tarball.sha256" )

common=(
  INSTALL_DIR="$install_dir"
  RELEASE_BASE="file://$release_src"
  SYSTEMCTL=/bin/true
  REQUIRE_ATTESTATION=0
  HEALTH_TIMEOUT=2
)

echo "--- scenario 1: fresh install succeeds"
env "${common[@]}" HEALTH_URL="file:///dev/null" bash "$here/update.sh"
[ -x "$install_dir/current/invidious" ] || { echo "FAIL: current/invidious missing"; exit 1; }
[ "$(readlink "$install_dir/current/config/config.yml")" = "$install_dir/config.yml" ] || { echo "FAIL: config symlink"; exit 1; }
first="$(readlink -f "$install_dir/current")"

echo "--- scenario 2: same release is a no-op"
out="$(env "${common[@]}" HEALTH_URL="file:///dev/null" bash "$here/update.sh")"
echo "$out" | grep -q "Nothing to do" || { echo "FAIL: expected no-op"; exit 1; }

echo "--- scenario 3: failing health check rolls back"
echo "changed" >> "$release_src/dist/invidious"
tar -czf "$release_src/$tarball" -C "$release_src/dist" .
( cd "$release_src" && sha256sum "$tarball" > "$tarball.sha256" )
if env "${common[@]}" HEALTH_URL="file:///nonexistent-health" bash "$here/update.sh"; then
  echo "FAIL: update should have failed"; exit 1
fi
[ "$(readlink -f "$install_dir/current")" = "$first" ] || { echo "FAIL: rollback did not restore previous release"; exit 1; }

echo "--- scenario 4: a failing switch still asks systemctl to start the service"
install_dir4="$tmp/install4"
mkdir -p "$install_dir4/current" && touch "$install_dir4/current/blocker"   # non-empty dir: mv -T onto it fails
echo "hmac_key: test" > "$install_dir4/config.yml"
fake_systemctl="$tmp/fake-systemctl"
printf '#!/bin/sh\necho "$1 $2" >> "%s"\n' "$tmp/systemctl.log" > "$fake_systemctl"
chmod +x "$fake_systemctl"
rm -f "$tmp/systemctl.log"
if env INSTALL_DIR="$install_dir4" RELEASE_BASE="file://$release_src" SYSTEMCTL="$fake_systemctl" REQUIRE_ATTESTATION=0 HEALTH_TIMEOUT=2 HEALTH_URL="file:///dev/null" bash "$here/update.sh"; then
  echo "FAIL: update should have failed on the blocked switch"; exit 1
fi
grep -q "^stop invidious" "$tmp/systemctl.log" || { echo "FAIL: service was never stopped"; exit 1; }
[ "$(tail -n 1 "$tmp/systemctl.log")" = "start invidious" ] || { echo "FAIL: trap did not restart the service"; exit 1; }

echo "ALL OK"

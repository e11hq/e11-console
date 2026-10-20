#!/usr/bin/env bash
# Build a release bundle: dist/e11-console-<version>.tar.gz (server + web), used by the launcher.
# Usage: scripts/bundle.sh 1.2.0 [notes-file]
set -euo pipefail
VERSION="${1:?version}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT_DIR:-$ROOT/dist}"
STAGE="$(mktemp -d)"
mkdir -p "$STAGE/e11-console/server" "$OUT"
cp -R "$ROOT/server/src" "$ROOT/server/package.json" "$STAGE/e11-console/server/"
cp -R "$ROOT/web" "$STAGE/e11-console/web"
cp -R "$ROOT/mac" "$STAGE/e11-console/mac"
echo "$VERSION" > "$STAGE/e11-console/VERSION"
if [ "${2:-}" != "" ] && [ -f "$2" ]; then cp "$2" "$STAGE/e11-console/RELEASE_NOTES.md"; fi
tar -czf "$OUT/e11-console-$VERSION.tar.gz" -C "$STAGE" e11-console
rm -rf "$STAGE"
echo "$OUT/e11-console-$VERSION.tar.gz"

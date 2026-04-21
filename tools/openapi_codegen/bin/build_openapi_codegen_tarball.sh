#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
STAMP="$(date +%Y%m%d_%H%M%S)"
TARBALL="$REPO_ROOT/tools/openapi_codegen/openapi_codegen_package_${STAMP}.tar.gz"

TMP_DIR="$(mktemp -d)"
PKG_DIR="$TMP_DIR/openapi_codegen_package"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$PKG_DIR/src/python"
mkdir -p "$PKG_DIR/bin"

cp "$REPO_ROOT/tools/openapi_codegen/bin/generate_sdn_vendor_from_openapi.py" "$PKG_DIR/bin/"
cp "$REPO_ROOT/tools/openapi_codegen/bin/build_openapi_codegen_tarball.sh" "$PKG_DIR/bin/"
cp "$REPO_ROOT/tools/openapi_codegen/src/python/netmri_sdn_openapi_codegen.py" "$PKG_DIR/src/python/"
cp "$REPO_ROOT/tools/openapi_codegen/WORKFLOW.md" "$PKG_DIR/"

chmod 755 "$PKG_DIR/bin/generate_sdn_vendor_from_openapi.py"
chmod 755 "$PKG_DIR/bin/build_openapi_codegen_tarball.sh"

tar -C "$TMP_DIR" -czf "$TARBALL" openapi_codegen_package

echo "$TARBALL"

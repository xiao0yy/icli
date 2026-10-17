#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -x dist/icli ]] || { echo 'Run scripts/build.sh first' >&2; exit 1; }
version="$(dist/icli --version)"
arch="$(lipo -archs dist/icli)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid binary version' >&2; exit 1; }
[[ "$arch" == arm64 || "$arch" == x86_64 ]] || { echo 'Expected one native architecture' >&2; exit 1; }
archive="icli-v${version}-macos-${arch}.tar.gz"
staging="$(mktemp -d "${TMPDIR:-/tmp}/icli-package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
cp dist/icli LICENSE README.md "$staging/"
COPYFILE_DISABLE=1 tar -czf "dist/$archive" -C "$staging" icli LICENSE README.md
(cd dist && shasum -a 256 "$archive" > "$archive.sha256")
printf 'Packaged dist/%s\n' "$archive"

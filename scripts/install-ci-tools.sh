#!/usr/bin/env bash
# Install checksum-verified release binaries used by the make lint targets.
#
# This exists because ci.yml and maintenance.yml both need these tools, and the
# install logic was previously duplicated byte-for-byte in both workflow files
# with nothing marking the copies as needing to stay in sync. Per AGENTS.md
# ("the Makefile is the only executable contract in this repository") and
# skills/github-actions-hygiene rule 1, this logic belongs here, not in YAML.
#
# Usage: scripts/install-ci-tools.sh <tool> [<tool>...]
#        make ci-tools TOOLS="actionlint gitleaks lychee"
#
# Known tools: actionlint, gitleaks, lychee
#
# CI-oriented installer. Local development is unchanged: the `make lint-*`
# targets still only *check* for these tools and print a brew/npm hint. Nothing
# invokes this script implicitly.
#
# INSTALL_DIR (default /usr/local/bin) can point at a throwaway prefix for
# testing. sudo is used only when the target is not writable by the caller.
#
# bash 3.2 portable (macOS default /bin/bash), matching scripts/bootstrap.sh:
# no associative arrays, no mapfile, no arrays-of-arrays.

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

# --- version pins -----------------------------------------------------------
# Single source of truth for the CI tool versions. These are NOT visible to
# Dependabot (there is no manifest for it to read), so they must be bumped by
# hand. Tracked separately as tool-version rot.
ACTIONLINT_VERSION="1.7.12"
GITLEAKS_VERSION="8.30.1"
LYCHEE_VERSION="0.24.2"

# --- preflight --------------------------------------------------------------
# Every asset below is a linux x86_64 build, which is correct for the
# ubuntu-latest hosted runners this repo uses. On any other architecture the
# download would succeed and then fail at exec time with a confusing "exec
# format error", so fail loudly and early instead. Supporting arm64 means adding
# per-tool asset names here, not relaxing this check.
require_supported_platform() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  if [ "$os" != "Linux" ] || { [ "$arch" != "x86_64" ] && [ "$arch" != "amd64" ]; }; then
    echo "error: install-ci-tools.sh only ships linux x86_64 assets (got ${os}/${arch})." >&2
    echo "       On other platforms, install these tools with your package manager;" >&2
    echo "       the make lint-* targets print the expected install hints." >&2
    exit 1
  fi
}

# --- helpers (moved verbatim from ci.yml / maintenance.yml) ------------------
verify_checksum() {
  local asset="$1" checksums="$2" line hash
  line="$(grep -F "$asset" "$checksums" || true)"
  if [ -z "$line" ]; then
    line="$(head -n 1 "$checksums")"
  fi
  hash="$(printf '%s\n' "$line" | grep -Eo '[A-Fa-f0-9]{64}' | head -n 1)"
  test -n "$hash"
  printf '%s  %s\n' "$hash" "$asset" | sha256sum -c -
}

place_binary() {
  # place_binary <source-path> <binary-name>
  local found="$1" binary="$2"
  if [ -w "$INSTALL_DIR" ]; then
    install -m 0755 "$found" "${INSTALL_DIR}/${binary}"
  else
    sudo install -m 0755 "$found" "${INSTALL_DIR}/${binary}"
  fi
}

install_tar_binary() {
  local repo="$1" tag="$2" asset="$3" checksums="$4" binary="$5"
  local url="https://github.com/${repo}/releases/download/${tag}"
  curl -fsSLO "$url/$asset"
  curl -fsSLO "$url/$checksums"
  verify_checksum "$asset" "$checksums"
  local extract_dir="${tmp}/extract-${binary}"
  mkdir -p "$extract_dir"
  tar -xzf "$asset" -C "$extract_dir"
  local found
  found="$(find "$extract_dir" -type f -name "$binary" -print -quit)"
  if [ -z "$found" ]; then
    echo "::error::binary '$binary' not found in $asset" >&2
    exit 1
  fi
  place_binary "$found" "$binary"
}

install_tool() {
  case "$1" in
    actionlint)
      install_tar_binary "rhysd/actionlint" "v${ACTIONLINT_VERSION}" \
        "actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" \
        "actionlint_${ACTIONLINT_VERSION}_checksums.txt" \
        "actionlint"
      ;;
    gitleaks)
      install_tar_binary "gitleaks/gitleaks" "v${GITLEAKS_VERSION}" \
        "gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
        "gitleaks_${GITLEAKS_VERSION}_checksums.txt" \
        "gitleaks"
      ;;
    lychee)
      install_tar_binary "lycheeverse/lychee" "lychee-v${LYCHEE_VERSION}" \
        "lychee-x86_64-unknown-linux-gnu.tar.gz" \
        "lychee-x86_64-unknown-linux-gnu.tar.gz.sha256" \
        "lychee"
      ;;
    *)
      echo "error: unknown tool '$1' (known: actionlint, gitleaks, lychee)" >&2
      exit 1
      ;;
  esac
}

# --- main -------------------------------------------------------------------
if [ "$#" -eq 0 ]; then
  echo "usage: $0 <tool> [<tool>...]   (known: actionlint, gitleaks, lychee)" >&2
  exit 1
fi

# Validate every requested tool up front so a typo fails instantly rather than
# halfway through a multi-tool install.
for tool in "$@"; do
  case "$tool" in
    actionlint | gitleaks | lychee) ;;
    *)
      echo "error: unknown tool '$tool' (known: actionlint, gitleaks, lychee)" >&2
      exit 1
      ;;
  esac
done

require_supported_platform

mkdir -p "$INSTALL_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

for tool in "$@"; do
  echo "installing ${tool} -> ${INSTALL_DIR}"
  install_tool "$tool"
done

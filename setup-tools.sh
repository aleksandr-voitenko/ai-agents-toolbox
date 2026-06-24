#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_NAME="$(uname -s)"

case "$OS_NAME" in
  Darwin)
    exec "$SCRIPT_DIR/macos.sh" "$@"
    ;;
  Linux)
    exec "$SCRIPT_DIR/linux.sh" "$@"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    cat <<'MSG'
Windows detected from a Unix-like shell.

Please run the PowerShell script instead:
  powershell -ExecutionPolicy Bypass -File .\windows.ps1
MSG
    exit 2
    ;;
  *)
    echo "Unsupported OS: $OS_NAME" >&2
    exit 2
    ;;
esac

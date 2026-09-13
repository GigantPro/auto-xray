set -Eeuo pipefail

: "${AUTO_XRAY_VERSION:=dev}"

ax_die() {
  printf 'auto-xray: %s\n' "$*" >&2
  exit 1
}

ax_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

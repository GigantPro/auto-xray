set -Eeuo pipefail

: "${AUTO_XRAY_VERSION:=dev}"
: "${AX_ETC_DIR:=/etc/auto-xray}"
: "${AX_STATE_DIR:=/var/lib/auto-xray}"
: "${AX_LOG_DIR:=/var/log/auto-xray}"
: "${AX_OPT_DIR:=/opt/auto-xray}"
: "${AX_BIN_LINK:=/usr/local/bin/auto-xray}"
: "${AX_SERVICE_NAME:=auto-xray}"

AX_CONFIG_FILE="$AX_ETC_DIR/config"
AX_SECRET_FILE="$AX_ETC_DIR/subscription-url"
AX_HWID_FILE="$AX_ETC_DIR/hwid"
AX_ACTIVE_CONFIG="$AX_STATE_DIR/active.json"
AX_LAST_GOOD_CONFIG="$AX_STATE_DIR/last-good.json"
AX_META_FILE="$AX_STATE_DIR/state"
AX_LOCK_FILE="$AX_STATE_DIR/update.lock"

ax_die() {
  printf 'auto-xray: %s\n' "$*" >&2
  exit 1
}

ax_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ax_trim() {
  local value=$1
  value=${value#"${value%%[![:space:]]*}"}
  value=${value%"${value##*[![:space:]]}"}
  printf '%s' "$value"
}

ax_bool() {
  case ${1,,} in true|yes|1|on) printf true ;; false|no|0|off) printf false ;; *) return 1 ;; esac
}

ax_quote() { printf '%q' "$1"; }

ax_secure_dir() {
  install -d -m "$2" "$1"
}

ax_write_atomic() {
  local target=$1 mode=$2 dir tmp
  dir=$(dirname -- "$target")
  mkdir -p "$dir"
  tmp=$(mktemp "$dir/.auto-xray.XXXXXX")
  chmod "$mode" "$tmp"
  cat >"$tmp"
  mv -f -- "$tmp" "$target"
}

ax_copy_atomic() {
  local source=$1 target=$2 mode=${3:-0600}
  ax_write_atomic "$target" "$mode" <"$source"
}

ax_read_kv() {
  local key=$1 file=${2:-$AX_CONFIG_FILE} line
  [[ -r $file ]] || return 1
  while IFS= read -r line; do
    [[ $line == "$key="* ]] || continue
    printf '%s\n' "${line#*=}"
    return 0
  done <"$file"
  return 1
}

ax_log() {
  local level=$1; shift
  local message=${*//$'\n'/ }
  printf '%s [%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$level" "$message" >&2
}

ax_init_directories() {
  umask 077
  ax_secure_dir "$AX_ETC_DIR" 0700
  ax_secure_dir "$AX_STATE_DIR" 0700
  ax_secure_dir "$AX_LOG_DIR" 0750
  ax_secure_dir "$AX_OPT_DIR" 0755
  ax_secure_dir "$AX_OPT_DIR/bin" 0755
}

ax_save_settings() {
  local tmp
  tmp=$(mktemp "$AX_ETC_DIR/.config.XXXXXX")
  chmod 0600 "$tmp"
  {
    printf 'DEPLOYMENT=%s\n' "$AX_DEPLOYMENT"
    printf 'XRAY_VERSION_MODE=%s\n' "$AX_XRAY_VERSION_MODE"
    printf 'XRAY_VERSION=%s\n' "$AX_XRAY_VERSION"
    printf 'XRAY_BIN=%s\n' "$AX_XRAY_BIN"
    printf 'PROFILE_REMARK=%s\n' "$(printf %s "$AX_PROFILE_REMARK" | base64 | tr -d '\n')"
    printf 'PROFILE_OCCURRENCE=%s\n' "$AX_PROFILE_OCCURRENCE"
    printf 'INTERVAL_MODE=%s\n' "$AX_INTERVAL_MODE"
    printf 'INTERVAL_HOURS=%s\n' "$AX_INTERVAL_HOURS"
    printf 'AUTOSTART=%s\n' "$AX_AUTOSTART"
    printf 'SCHEDULER=%s\n' "$AX_SCHEDULER"
    printf 'USER_AGENT=%s\n' "$AX_USER_AGENT"
    printf 'HEALTH_URLS=%s\n' "$(printf %s "$AX_HEALTH_URLS" | base64 | tr -d '\n')"
  } >"$tmp"
  mv -f -- "$tmp" "$AX_CONFIG_FILE"
}

ax_load_settings() {
  [[ -r $AX_CONFIG_FILE ]] || ax_die "auto-xray is not configured"
  AX_DEPLOYMENT=$(ax_read_kv DEPLOYMENT)
  AX_XRAY_VERSION_MODE=$(ax_read_kv XRAY_VERSION_MODE)
  AX_XRAY_VERSION=$(ax_read_kv XRAY_VERSION)
  AX_XRAY_BIN=$(ax_read_kv XRAY_BIN)
  AX_PROFILE_REMARK=$(ax_read_kv PROFILE_REMARK | base64 -d)
  AX_PROFILE_OCCURRENCE=$(ax_read_kv PROFILE_OCCURRENCE)
  AX_INTERVAL_MODE=$(ax_read_kv INTERVAL_MODE)
  AX_INTERVAL_HOURS=$(ax_read_kv INTERVAL_HOURS)
  AX_AUTOSTART=$(ax_read_kv AUTOSTART)
  AX_SCHEDULER=$(ax_read_kv SCHEDULER)
  AX_USER_AGENT=$(ax_read_kv USER_AGENT)
  AX_HEALTH_URLS=$(ax_read_kv HEALTH_URLS | base64 -d)
}

ax_save_subscription_url() {
  local url=$1
  [[ $url == https://* || ${AX_ALLOW_HTTP:-false} == true ]] || ax_die "subscription URL must use HTTPS"
  printf '%s\n' "$url" | ax_write_atomic "$AX_SECRET_FILE" 0600
}

ax_ensure_hwid() {
  if [[ ! -s $AX_HWID_FILE ]]; then
    local value
    if [[ -r /proc/sys/kernel/random/uuid ]]; then value=$(tr -d '-' </proc/sys/kernel/random/uuid)
    else value=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n'); fi
    printf '%s\n' "$value" | ax_write_atomic "$AX_HWID_FILE" 0600
  fi
  AX_HWID=$(<"$AX_HWID_FILE")
  [[ $AX_HWID =~ ^[A-Za-z0-9=-]{10,64}$ ]] || ax_die "stored HWID is invalid"
}

ax_save_runtime_state() {
  local active_remark=$1 active_index=$2 last_success=$3 next_update=$4
  {
    printf 'ACTIVE_REMARK=%s\n' "$(printf %s "$active_remark" | base64 | tr -d '\n')"
    printf 'ACTIVE_INDEX=%s\n' "$active_index"
    printf 'LAST_SUCCESS=%s\n' "$last_success"
    printf 'NEXT_UPDATE=%s\n' "$next_update"
  } | ax_write_atomic "$AX_META_FILE" 0600
}

ax_state_value() { ax_read_kv "$1" "$AX_META_FILE" 2>/dev/null || true; }

#!/usr/bin/env bash
# AUTO_XRAY_LIBRARIES
if [[ -z ${AUTO_XRAY_BUNDLED:-} ]]; then
  _ax_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
  for _ax_lib in "$_ax_root"/src/lib/*.sh; do source "$_ax_lib"; done
  unset _ax_root _ax_lib
fi

AX_ORIGINAL_ARGS=("$@")
AX_INTERACTIVE=true
AX_INSTALL_DEPS=false
AX_ASSUME_YES=false
AX_DEPLOYMENT=''
AX_XRAY_VERSION_CHOICE=recommended
AX_XRAY_VERSION_SET=false
AX_SUBSCRIPTION_INPUT=''
AX_SUBSCRIPTION_FILE=''
AX_PROFILE_CHOICE=''
AX_INTERVAL_MODE=subscription
AX_INTERVAL_HOURS=12
AX_AUTOSTART=true
AX_SCHEDULER=''
AX_USER_AGENT=Happ/auto-xray
AX_HEALTH_URLS='https://cp.cloudflare.com/generate_204 https://www.gstatic.com/generate_204'

ax_usage() {
  cat <<EOF
auto-xray $AUTO_XRAY_VERSION — manage Xray from a Remnawave XRAY_JSON subscription

Usage:
  auto-xray                         Interactive installer
  auto-xray install [OPTIONS]
  auto-xray configure [OPTIONS]
  auto-xray update [--scheduled]
  auto-xray core-upgrade --xray-version VERSION
  auto-xray status|logs|start|stop|restart|uninstall

Install options:
  --non-interactive
  --deployment host|docker
  --xray-version recommended|latest|installed|VERSION
  --subscription-url URL | --subscription-url-file FILE
  --profile INDEX|REMARK
  --interval subscription|1h|12h
  --autostart true|false
  --scheduler systemd|cron
  --install-deps
  --yes
EOF
}

ax_parse_options() {
  while (( $# )); do
    case $1 in
      --non-interactive) AX_INTERACTIVE=false ;;
      --install-deps) AX_INSTALL_DEPS=true ;;
      --yes) AX_ASSUME_YES=true ;;
      --deployment) [[ $# -ge 2 ]] || ax_die "$1 requires a value"; AX_DEPLOYMENT=$2; shift ;;
      --xray-version) [[ $# -ge 2 ]] || ax_die "$1 requires a value"; AX_XRAY_VERSION_CHOICE=$2; AX_XRAY_VERSION_SET=true; shift ;;
      --subscription-url) [[ $# -ge 2 ]] || ax_die "$1 requires a value"; AX_SUBSCRIPTION_INPUT=$2; shift ;;
      --subscription-url-file) [[ $# -ge 2 ]] || ax_die "$1 requires a value"; AX_SUBSCRIPTION_FILE=$2; shift ;;
      --profile) [[ $# -ge 2 ]] || ax_die "$1 requires a value"; AX_PROFILE_CHOICE=$2; shift ;;
      --interval) [[ $# -ge 2 ]] || ax_die "$1 requires a value"; AX_INTERVAL_MODE=$2; shift ;;
      --autostart) [[ $# -ge 2 ]] || ax_die "$1 requires a value"; AX_AUTOSTART=$(ax_bool "$2") || ax_die "invalid --autostart value"; shift ;;
      --scheduler) [[ $# -ge 2 ]] || ax_die "$1 requires a value"; AX_SCHEDULER=$2; shift ;;
      --health-url) [[ $# -ge 2 ]] || ax_die "$1 requires a value"; AX_HEALTH_URLS=$2; shift ;;
      --scheduled) AX_SCHEDULED=true ;;
      --follow|-f) AX_FOLLOW=true ;;
      --help|-h) ax_usage; exit 0 ;;
      *) ax_die "unknown option: $1" ;;
    esac
    shift
  done
}

ax_validate_choices() {
  [[ $AX_DEPLOYMENT =~ ^(host|docker)$ ]] || ax_die "--deployment must be host or docker"
  [[ $AX_SCHEDULER =~ ^(systemd|cron)$ ]] || ax_die "--scheduler must be systemd or cron"
  case $AX_INTERVAL_MODE in
    subscription) AX_INTERVAL_HOURS=${AX_INTERVAL_HOURS:-12} ;;
    1h) AX_INTERVAL_HOURS=1 ;;
    12h) AX_INTERVAL_HOURS=12 ;;
    *) ax_die "--interval must be subscription, 1h, or 12h" ;;
  esac
}

ax_read_subscription_input() {
  if [[ -n $AX_SUBSCRIPTION_FILE ]]; then
    [[ -r $AX_SUBSCRIPTION_FILE ]] || ax_die "cannot read subscription URL file"
    AX_SUBSCRIPTION_INPUT=$(<"$AX_SUBSCRIPTION_FILE")
  fi
  AX_SUBSCRIPTION_INPUT=$(ax_trim "$AX_SUBSCRIPTION_INPUT")
  [[ -n $AX_SUBSCRIPTION_INPUT ]] || ax_die "subscription URL is required"
}

ax_choose_profile_index() {
  local subscription=$1 count index i remark
  count=$(ax_profile_count "$subscription")
  if [[ $AX_PROFILE_CHOICE =~ ^[0-9]+$ ]]; then
    index=$((AX_PROFILE_CHOICE - 1))
    (( index >= 0 && index < count )) || ax_die "profile index is out of range"
    printf '%s\n' "$index"; return
  fi
  for ((i=0; i<count; i++)); do
    remark=$(ax_profile_remark "$subscription" "$i")
    if [[ $remark == "$AX_PROFILE_CHOICE" ]]; then printf '%s\n' "$i"; return; fi
  done
  ax_die "profile was not found: $AX_PROFILE_CHOICE"
}

ax_fetch_for_setup() {
  AX_SETUP_TEMP=$(mktemp -d "$AX_STATE_DIR/.setup.XXXXXX")
  AX_SETUP_BODY="$AX_SETUP_TEMP/subscription.json"
  AX_SETUP_HEADERS="$AX_SETUP_TEMP/headers"
  ax_step subscription 'Downloading subscription metadata'
  ax_fetch_subscription "$AX_SETUP_BODY" "$AX_SETUP_HEADERS"
  ax_validate_subscription "$AX_SETUP_BODY"
}

ax_interactive_choices() {
  local selected latest installed interval_from_sub
  selected=$(ax_select 'Where should Xray run?' 'Host machine (recommended)' 'Docker') || ax_die "selection cancelled"
  [[ $selected == 0 ]] && AX_DEPLOYMENT=host || AX_DEPLOYMENT=docker
  if [[ $AX_DEPLOYMENT == docker ]] && ! ax_command_exists docker; then ax_die "Docker Engine must be installed manually"; fi

  latest=$(ax_latest_xray_version 2>/dev/null || true)
  local -a labels=("26.7.28 (recommended)") values=(recommended)
  [[ -n $latest ]] && { labels+=("$latest (latest, prereleases included)"); values+=(latest); }
  if [[ $AX_DEPLOYMENT == host ]]; then
    installed=$(ax_installed_xray 2>/dev/null || true)
    [[ -n $installed ]] && { labels+=("${installed%%$'\t'*} (installed)"); values+=(installed); }
  fi
  selected=$(ax_select 'Choose Xray version' "${labels[@]}") || ax_die "selection cancelled"
  AX_XRAY_VERSION_CHOICE=${values[selected]}

  AX_SUBSCRIPTION_INPUT=$(ax_prompt 'Paste the subscription URL' '' true)
  ax_read_subscription_input
  ax_save_subscription_url "$AX_SUBSCRIPTION_INPUT"
  ax_fetch_for_setup

  mapfile -t labels < <(ax_list_profiles "$AX_SETUP_BODY")
  selected=$(ax_select 'Choose a profile' "${labels[@]}") || ax_die "selection cancelled"
  AX_PROFILE_CHOICE=$((selected + 1))

  interval_from_sub=$(ax_subscription_interval "$AX_SETUP_HEADERS")
  labels=("$interval_from_sub hour(s) (subscription recommendation)"); values=(subscription)
  [[ $interval_from_sub != 1 ]] && { labels+=('1 hour'); values+=(1h); }
  [[ $interval_from_sub != 12 ]] && { labels+=('12 hours'); values+=(12h); }
  selected=$(ax_select 'Choose subscription update interval' "${labels[@]}") || ax_die "selection cancelled"
  AX_INTERVAL_MODE=${values[selected]}
  [[ $AX_INTERVAL_MODE == subscription ]] && AX_INTERVAL_HOURS=$interval_from_sub
  [[ $AX_INTERVAL_MODE == 1h ]] && AX_INTERVAL_HOURS=1
  [[ $AX_INTERVAL_MODE == 12h ]] && AX_INTERVAL_HOURS=12

  selected=$(ax_select 'Start Xray automatically at boot?' 'Yes (recommended)' 'No') || ax_die "selection cancelled"
  [[ $selected == 0 ]] && AX_AUTOSTART=true || AX_AUTOSTART=false
  selected=$(ax_select 'Manage startup and updates with' 'systemd (recommended)' 'cron') || ax_die "selection cancelled"
  [[ $selected == 0 ]] && AX_SCHEDULER=systemd || AX_SCHEDULER=cron
}

ax_install_command() {
  local mode=$1 old_deployment=''; shift || true
  ax_parse_options "$@"
  ax_detect_platform
  ax_require_root "$AX_INTERACTIVE"
  ax_init_directories
  ax_require_dependencies '' host "$AX_INSTALL_DEPS" "$AX_INTERACTIVE"
  ax_ensure_hwid
  if [[ $AX_INTERACTIVE == true ]]; then
    ax_interactive_choices
  else
    ax_validate_choices
    ax_read_subscription_input
    [[ -n $AX_PROFILE_CHOICE ]] || ax_die "--profile is required in non-interactive mode"
    ax_save_subscription_url "$AX_SUBSCRIPTION_INPUT"
    ax_fetch_for_setup
  fi
  ax_validate_choices
  ax_require_dependencies "$AX_SCHEDULER" "$AX_DEPLOYMENT" "$AX_INSTALL_DEPS" "$AX_INTERACTIVE"
  if [[ $mode == configure && -r $AX_CONFIG_FILE ]]; then
    old_deployment=$(ax_read_kv DEPLOYMENT)
    [[ $old_deployment == "$AX_DEPLOYMENT" ]] || ax_die "changing deployment mode requires uninstall followed by install"
  fi
  ax_resolve_xray_version "$AX_XRAY_VERSION_CHOICE"
  ax_prepare_xray
  if [[ $mode == configure && -n $old_deployment ]]; then ax_runtime_stop; ax_remove_scheduler; fi
  local profile_index
  profile_index=$(ax_choose_profile_index "$AX_SETUP_BODY")
  AX_PROFILE_REMARK=$(ax_profile_remark "$AX_SETUP_BODY" "$profile_index")
  AX_PROFILE_OCCURRENCE=$(ax_remark_occurrence "$AX_SETUP_BODY" "$profile_index")
  ax_step validate 'Validating profiles and proxy connectivity'
  if ! ax_apply_subscription "$AX_SETUP_BODY" "$AX_SETUP_HEADERS" "$profile_index" true; then
    rm -rf -- "$AX_SETUP_TEMP"; ax_die "no working subscription profile was found"
  fi
  ax_save_settings
  ax_install_scheduler
  rm -rf -- "$AX_SETUP_TEMP"
  ax_ok "Installed Xray $AX_XRAY_VERSION; active profile: $AX_PROFILE_REMARK"
}

ax_load_for_command() {
  ax_detect_platform
  ax_require_root false
  ax_init_directories
  ax_load_settings
}

ax_status_command() {
  ax_load_for_command
  local active next status=stopped
  active=$(ax_state_value ACTIVE_REMARK | base64 -d 2>/dev/null || true)
  next=$(ax_state_value NEXT_UPDATE)
  ax_runtime_is_running && status=running
  printf 'auto-xray: %s\ndeployment: %s\nxray: %s\npreferred profile: %s\nactive profile: %s\nupdate interval: %sh (%s)\n' \
    "$status" "$AX_DEPLOYMENT" "$AX_XRAY_VERSION" "$AX_PROFILE_REMARK" "${active:-unknown}" "$AX_INTERVAL_HOURS" "$AX_INTERVAL_MODE"
  [[ $next =~ ^[0-9]+$ ]] && printf 'next update: %s\n' "$(date -d "@$next" '+%F %T %Z' 2>/dev/null || printf '%s' "$next")"
}

ax_logs_command() {
  ax_load_for_command
  if [[ ${AX_FOLLOW:-false} == true ]]; then
    [[ $AX_DEPLOYMENT == docker ]] && exec docker logs -f "$AX_CONTAINER_NAME"
    exec tail -F "$AX_RUNTIME_LOG" "$AX_APP_LOG"
  fi
  ax_runtime_logs 100
  tail -n 100 "$AX_APP_LOG" 2>/dev/null || true
}

ax_core_upgrade() {
  ax_parse_options "$@"
  [[ $AX_XRAY_VERSION_SET == true ]] || ax_die "core-upgrade requires --xray-version"
  ax_load_for_command
  local was_running=false old_bin=$AX_XRAY_BIN old_version=$AX_XRAY_VERSION old_mode=$AX_XRAY_VERSION_MODE
  ax_runtime_is_running && was_running=true
  ax_resolve_xray_version "$AX_XRAY_VERSION_CHOICE"
  ax_prepare_xray
  if ! ax_xray_test_config "$AX_ACTIVE_CONFIG"; then
    AX_XRAY_BIN=$old_bin; AX_XRAY_VERSION=$old_version; AX_XRAY_VERSION_MODE=$old_mode
    ax_die "active config is incompatible with requested Xray version"
  fi
  [[ $was_running == true ]] && ax_runtime_stop
  ax_save_settings
  [[ $was_running == true ]] && ax_runtime_start
  ax_ok "Xray core is now $AX_XRAY_VERSION"
}

ax_uninstall_command() {
  ax_parse_options "$@"
  ax_load_for_command
  if [[ $AX_ASSUME_YES != true ]]; then
    [[ $AX_INTERACTIVE == true ]] || ax_die "non-interactive uninstall requires --yes"
    ax_confirm 'Remove the auto-xray installation?' || exit 0
  fi
  ax_runtime_stop
  ax_remove_scheduler
  rm -f -- "$AX_BIN_LINK"
  rm -rf -- "$AX_ETC_DIR" "$AX_STATE_DIR" "$AX_LOG_DIR" "$AX_OPT_DIR"
  ax_ok 'Removed auto-xray managed files; system packages and external Xray were preserved'
}

main() {
  local command=${1:-install}
  if [[ $# -gt 0 ]]; then shift; fi
  case $command in
    install) [[ -e $AX_CONFIG_FILE ]] && ax_die "already installed; use configure"; ax_install_command install "$@" ;;
    configure) ax_install_command configure "$@" ;;
    update) ax_parse_options "$@"; ax_load_for_command; ax_require_dependencies "$AX_SCHEDULER" "$AX_DEPLOYMENT" false false; ax_rotate_logs; ax_update_subscription "$([[ ${AX_SCHEDULED:-false} == true ]] && printf false || printf true)" ;;
    core-upgrade) ax_core_upgrade "$@" ;;
    status) ax_status_command ;;
    logs) ax_parse_options "$@"; ax_logs_command ;;
    start|internal-start) ax_load_for_command; ax_runtime_start ;;
    stop|internal-stop) ax_load_for_command; ax_runtime_stop ;;
    restart) ax_load_for_command; ax_runtime_stop; ax_runtime_start ;;
    uninstall) ax_uninstall_command "$@" ;;
    --version|-V) printf 'auto-xray %s\n' "$AUTO_XRAY_VERSION" ;;
    --help|-h|help) ax_usage ;;
    *) ax_die "unknown command: $command" ;;
  esac
}

main "$@"

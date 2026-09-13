ax_candidate_order() {
  local subscription=$1 preferred_index=${2:-} count i
  count=$(ax_profile_count "$subscription")
  if [[ $preferred_index =~ ^[0-9]+$ ]] && (( preferred_index < count )); then printf '%s\n' "$preferred_index"; fi
  for ((i=0; i<count; i++)); do [[ $i == "$preferred_index" ]] || printf '%s\n' "$i"; done
}

ax_try_candidate() {
  local subscription=$1 index=$2 candidate=$3
  ax_extract_profile "$subscription" "$index" "$candidate"
  ax_xray_test_config "$candidate" || { ax_log WARN "profile index $((index+1)) failed Xray syntax validation"; return 1; }
  ax_copy_atomic "$candidate" "$AX_ACTIVE_CONFIG" 0600
  ax_runtime_start "$AX_ACTIVE_CONFIG" || { ax_log WARN "profile index $((index+1)) failed to start"; return 1; }
  ax_wait_runtime || { ax_log WARN "profile index $((index+1)) exited during startup"; ax_runtime_stop; return 1; }
  ax_health_check "$AX_ACTIVE_CONFIG" || { ax_log WARN "profile index $((index+1)) failed proxy health check"; ax_runtime_stop; return 1; }
}

ax_apply_subscription() {
  local subscription=$1 headers=$2 initial_index=${3:-} keep_running=${4:-true}
  local preferred_index='' index candidate remark now next interval old_running=false had_old=false success=false
  candidate=$(mktemp --suffix=.json "$AX_STATE_DIR/.candidate.XXXXXX")
  chmod 0600 "$candidate"
  [[ -s $AX_ACTIVE_CONFIG ]] && { ax_copy_atomic "$AX_ACTIVE_CONFIG" "$AX_LAST_GOOD_CONFIG" 0600; had_old=true; }
  ax_runtime_is_running && old_running=true

  if [[ -n $initial_index ]]; then preferred_index=$initial_index
  else preferred_index=$(ax_find_preferred_index "$subscription" "$AX_PROFILE_REMARK" "$AX_PROFILE_OCCURRENCE" 2>/dev/null || true); fi

  ax_runtime_stop
  while IFS= read -r index; do
    [[ $index =~ ^[0-9]+$ ]] || continue
    ax_step profile "Testing profile $((index+1))/$(ax_profile_count "$subscription")"
    if ax_try_candidate "$subscription" "$index" "$candidate"; then
      remark=$(ax_profile_remark "$subscription" "$index")
      ax_copy_atomic "$AX_ACTIVE_CONFIG" "$AX_LAST_GOOD_CONFIG" 0600
      interval=$AX_INTERVAL_HOURS
      [[ $AX_INTERVAL_MODE == subscription ]] && interval=$(ax_subscription_interval "$headers")
      AX_INTERVAL_HOURS=$interval
      now=$(date +%s); next=$((now + interval * 3600))
      ax_save_runtime_state "$remark" "$index" "$now" "$next"
      [[ $keep_running == true ]] || ax_runtime_stop
      ax_log INFO "subscription update activated profile index $((index+1))"
      success=true
      break
    fi
  done < <(ax_candidate_order "$subscription" "$preferred_index")
  rm -f -- "$candidate"

  if [[ $success != true ]]; then
    ax_runtime_stop
    if [[ $had_old == true ]]; then
      ax_copy_atomic "$AX_LAST_GOOD_CONFIG" "$AX_ACTIVE_CONFIG" 0600
      [[ $old_running == true ]] && ax_runtime_start "$AX_ACTIVE_CONFIG" || true
    else
      rm -f -- "$AX_ACTIVE_CONFIG"
    fi
    ax_log ERROR "all subscription profiles failed; previous config restored"
    return 1
  fi
}

ax_update_subscription() {
  local force=${1:-false} tempdir body headers next keep_running=false
  next=$(ax_state_value NEXT_UPDATE)
  if [[ $force != true && $next =~ ^[0-9]+$ && $(date +%s) -lt $next ]]; then return 0; fi
  exec 9>"$AX_LOCK_FILE"
  flock -n 9 || { ax_log INFO "another update is already running"; return 0; }
  ax_runtime_is_running && keep_running=true
  [[ $AX_AUTOSTART == true ]] && keep_running=true
  tempdir=$(mktemp -d "$AX_STATE_DIR/.update.XXXXXX")
  body="$tempdir/subscription.json"; headers="$tempdir/headers"
  if ! ax_fetch_subscription "$body" "$headers"; then rm -rf -- "$tempdir"; ax_log ERROR "subscription download failed"; return 1; fi
  if ! ax_validate_subscription "$body"; then rm -rf -- "$tempdir"; return 1; fi
  local result=0
  ax_apply_subscription "$body" "$headers" '' "$keep_running" || result=$?
  rm -rf -- "$tempdir"
  return "$result"
}

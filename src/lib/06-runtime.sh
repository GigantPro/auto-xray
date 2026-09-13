AX_PID_FILE="$AX_STATE_DIR/xray.pid"
AX_RUNTIME_LOG="$AX_LOG_DIR/xray.log"
AX_APP_LOG="$AX_LOG_DIR/auto-xray.log"
AX_CONTAINER_NAME=auto-xray

ax_host_is_running() {
  local pid
  [[ -r $AX_PID_FILE ]] || return 1
  pid=$(<"$AX_PID_FILE")
  [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

ax_host_start() {
  local config=${1:-$AX_ACTIVE_CONFIG} pid
  ax_host_is_running && return 0
  [[ -x $AX_XRAY_BIN ]] || ax_die "Xray binary is unavailable: $AX_XRAY_BIN"
  nohup "$AX_XRAY_BIN" run -config "$config" >>"$AX_RUNTIME_LOG" 2>&1 &
  pid=$!
  printf '%s\n' "$pid" | ax_write_atomic "$AX_PID_FILE" 0600
}

ax_host_stop() {
  local pid i
  [[ -r $AX_PID_FILE ]] || return 0
  pid=$(<"$AX_PID_FILE")
  if [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    for ((i=0; i<50; i++)); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f -- "$AX_PID_FILE"
}

ax_docker_is_running() {
  [[ $(docker inspect -f '{{.State.Running}}' "$AX_CONTAINER_NAME" 2>/dev/null || true) == true ]]
}

ax_docker_start() {
  local config=${1:-$AX_ACTIVE_CONFIG}
  ax_docker_is_running && return 0
  docker rm -f "$AX_CONTAINER_NAME" >/dev/null 2>&1 || true
  docker run -d --name "$AX_CONTAINER_NAME" --network host --user 0:0 \
    --label io.auto-xray.managed=true \
    --mount "type=bind,src=$config,dst=/etc/xray/config.json,readonly" \
    "$AX_XRAY_BIN" run -config /etc/xray/config.json >/dev/null
}

ax_docker_stop() { docker rm -f "$AX_CONTAINER_NAME" >/dev/null 2>&1 || true; }

ax_runtime_is_running() {
  if [[ $AX_DEPLOYMENT == docker ]]; then ax_docker_is_running; else ax_host_is_running; fi
}

ax_runtime_start() {
  [[ -s ${1:-$AX_ACTIVE_CONFIG} ]] || ax_die "active Xray config is missing"
  if [[ $AX_DEPLOYMENT == docker ]]; then ax_docker_start "${1:-$AX_ACTIVE_CONFIG}"
  else ax_host_start "${1:-$AX_ACTIVE_CONFIG}"; fi
}

ax_runtime_stop() {
  if [[ $AX_DEPLOYMENT == docker ]]; then ax_docker_stop; else ax_host_stop; fi
}

ax_runtime_logs() {
  if [[ $AX_DEPLOYMENT == docker ]]; then docker logs --tail "${1:-100}" "$AX_CONTAINER_NAME" 2>&1 || true
  else tail -n "${1:-100}" "$AX_RUNTIME_LOG" 2>/dev/null || true; fi
}

ax_wait_runtime() {
  local i
  for ((i=0; i<50; i++)); do
    ax_runtime_is_running || return 1
    sleep 0.2
    (( i >= 9 )) && return 0
  done
  return 1
}

ax_proxy_endpoint() {
  local config=$1 protocol port
  protocol=$(jq -r '[.inbounds[]? | select(.protocol == "socks" or .protocol == "http")][0].protocol // empty' "$config")
  port=$(jq -r '[.inbounds[]? | select(.protocol == "socks" or .protocol == "http")][0].port // empty' "$config")
  [[ $protocol =~ ^(socks|http)$ && $port =~ ^[0-9]+$ ]] || return 1
  printf '%s\t%s\n' "$protocol" "$port"
}

ax_health_check() {
  local config=${1:-$AX_ACTIVE_CONFIG} endpoint protocol port url proxy
  endpoint=$(ax_proxy_endpoint "$config") || return 1
  protocol=${endpoint%%$'\t'*}; port=${endpoint#*$'\t'}
  [[ $protocol == socks ]] && proxy="socks5h://127.0.0.1:$port" || proxy="http://127.0.0.1:$port"
  for url in $AX_HEALTH_URLS; do
    curl --fail --silent --show-error --output /dev/null --proxy "$proxy" \
      --connect-timeout 8 --max-time 15 --proto '=https' --proto-redir '=https' "$url" 2>/dev/null && return 0
  done
  return 1
}

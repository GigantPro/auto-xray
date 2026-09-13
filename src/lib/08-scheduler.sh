AX_SYSTEMD_DIR=${AX_SYSTEMD_DIR:-/etc/systemd/system}
AX_CRON_FILE=${AX_CRON_FILE:-/etc/cron.d/auto-xray}

ax_install_launcher() {
  local source=$0
  [[ -r $source ]] || ax_die "cannot read launcher source"
  install -m 0755 "$source" "$AX_BIN_LINK"
}

ax_write_systemd_units() {
  {
    printf '%s\n' '[Unit]' 'Description=Auto-Xray managed Xray runtime' 'After=network-online.target' 'Wants=network-online.target' ''
    printf '%s\n' '[Service]' 'Type=oneshot' 'RemainAfterExit=yes'
    printf 'ExecStart=%s internal-start\n' "$AX_BIN_LINK"
    printf 'ExecStop=%s internal-stop\n' "$AX_BIN_LINK"
    printf '%s\n' 'TimeoutStartSec=60' 'TimeoutStopSec=30' '' '[Install]' 'WantedBy=multi-user.target'
  } | ax_write_atomic "$AX_SYSTEMD_DIR/$AX_SERVICE_NAME.service" 0644
  {
    printf '%s\n' '[Unit]' 'Description=Refresh Auto-Xray subscription' 'After=network-online.target' 'Wants=network-online.target' ''
    printf '%s\n' '[Service]' 'Type=oneshot'
    printf 'ExecStart=%s update --scheduled\n' "$AX_BIN_LINK"
  } | ax_write_atomic "$AX_SYSTEMD_DIR/$AX_SERVICE_NAME-update.service" 0644
  {
    printf '%s\n' '[Unit]' 'Description=Check whether Auto-Xray subscription update is due' ''
    printf '%s\n' '[Timer]' 'OnBootSec=5min' 'OnUnitActiveSec=1h' 'RandomizedDelaySec=5min' 'Persistent=true' ''
    printf '%s\n' '[Install]' 'WantedBy=timers.target'
  } | ax_write_atomic "$AX_SYSTEMD_DIR/$AX_SERVICE_NAME-update.timer" 0644
  systemctl daemon-reload
  systemctl enable --now "$AX_SERVICE_NAME-update.timer" >/dev/null
  if [[ $AX_AUTOSTART == true ]]; then systemctl enable "$AX_SERVICE_NAME.service" >/dev/null
  else systemctl disable "$AX_SERVICE_NAME.service" >/dev/null 2>&1 || true; fi
}

ax_write_cron() {
  {
    printf '%s\n' 'SHELL=/bin/bash' 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
    if [[ $AX_AUTOSTART == true ]]; then
      printf '@reboot root %s internal-start >>%s 2>&1\n' "$AX_BIN_LINK" "$AX_APP_LOG"
    fi
    printf '17 * * * * root %s update --scheduled >>%s 2>&1\n' "$AX_BIN_LINK" "$AX_APP_LOG"
  } | ax_write_atomic "$AX_CRON_FILE" 0644
}

ax_install_scheduler() {
  ax_install_launcher
  if [[ $AX_SCHEDULER == systemd ]]; then
    rm -f -- "$AX_CRON_FILE"
    ax_write_systemd_units
  else
    if ax_command_exists systemctl; then
      systemctl disable --now "$AX_SERVICE_NAME-update.timer" "$AX_SERVICE_NAME.service" >/dev/null 2>&1 || true
    fi
    ax_write_cron
  fi
}

ax_remove_scheduler() {
  if ax_command_exists systemctl; then
    systemctl disable --now "$AX_SERVICE_NAME-update.timer" "$AX_SERVICE_NAME.service" >/dev/null 2>&1 || true
  fi
  rm -f -- "$AX_SYSTEMD_DIR/$AX_SERVICE_NAME.service" \
    "$AX_SYSTEMD_DIR/$AX_SERVICE_NAME-update.service" \
    "$AX_SYSTEMD_DIR/$AX_SERVICE_NAME-update.timer" "$AX_CRON_FILE"
  ax_command_exists systemctl && systemctl daemon-reload || true
}

ax_rotate_logs() {
  local file
  for file in "$AX_RUNTIME_LOG" "$AX_APP_LOG"; do
    [[ -f $file ]] || continue
    if (( $(wc -c <"$file") > 5242880 )); then mv -f -- "$file" "$file.1"; : >"$file"; chmod 0640 "$file"; fi
  done
}

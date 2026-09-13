AX_OS_ID=''; AX_OS_VERSION=''; AX_XRAY_ASSET=''; AX_PACKAGE_MANAGER=''

ax_detect_platform() {
  [[ $(uname -s) == Linux ]] || ax_die "only Linux is supported"
  [[ -r /etc/os-release ]] || ax_die "cannot identify distribution"
  # shellcheck disable=SC1091
  source /etc/os-release
  AX_OS_ID=${ID:-unknown}; AX_OS_VERSION=${VERSION_ID:-rolling}
  case $AX_OS_ID in
    debian)
      case $AX_OS_VERSION in 11|12|13) ;; *) ax_die "unsupported Debian version: $AX_OS_VERSION" ;; esac
      AX_PACKAGE_MANAGER=apt ;;
    ubuntu) AX_PACKAGE_MANAGER=apt ;;
    arch|archlinux) AX_OS_ID=arch; AX_PACKAGE_MANAGER=pacman ;;
    *) ax_die "unsupported distribution: $AX_OS_ID" ;;
  esac
  case $(uname -m) in
    x86_64|amd64) AX_XRAY_ASSET=Xray-linux-64.zip ;;
    aarch64|arm64) AX_XRAY_ASSET=Xray-linux-arm64-v8a.zip ;;
    *) ax_die "unsupported architecture: $(uname -m)" ;;
  esac
}

ax_missing_dependencies() {
  local scheduler=${1:-} deployment=${2:-host} command
  local -a wanted=(curl jq unzip flock)
  [[ $scheduler == cron ]] && wanted+=(crontab)
  [[ $scheduler == systemd ]] && wanted+=(systemctl)
  [[ $deployment == docker ]] && wanted+=(docker)
  for command in "${wanted[@]}"; do ax_command_exists "$command" || printf '%s\n' "$command"; done
  [[ -r /etc/ssl/certs/ca-certificates.crt || -r /etc/ssl/cert.pem ]] || printf '%s\n' ca-certificates
}

ax_dependency_packages() {
  local scheduler=${1:-} missing=${2:-}
  local -a packages=(curl jq unzip ca-certificates util-linux)
  if [[ $scheduler == cron ]]; then
    [[ $AX_PACKAGE_MANAGER == apt ]] && packages+=(cron) || packages+=(cronie)
  fi
  printf '%s\n' "${packages[*]}"
}

ax_install_dependencies() {
  local scheduler=$1 package_line
  local -a packages
  package_line=$(ax_dependency_packages "$scheduler")
  read -r -a packages <<<"$package_line"
  ax_info "Installing required packages: ${packages[*]}"
  case $AX_PACKAGE_MANAGER in
    apt) DEBIAN_FRONTEND=noninteractive apt-get update; DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}" ;;
    pacman) pacman -S --needed --noconfirm "${packages[@]}" ;;
  esac
}

ax_require_dependencies() {
  local scheduler=$1 deployment=$2 allow_install=$3 interactive=$4 missing
  missing=$(ax_missing_dependencies "$scheduler" "$deployment" || true)
  [[ -z $missing ]] && return 0
  if grep -qx docker <<<"$missing"; then
    ax_die "Docker Engine is required and must be installed manually"
  fi
  ax_warn "Missing dependencies: $(tr '\n' ' ' <<<"$missing")"
  if [[ $allow_install == true ]]; then ax_install_dependencies "$scheduler"
  elif [[ $interactive == true ]] && ax_confirm "Install the missing packages?"; then ax_install_dependencies "$scheduler"
  else ax_die "dependencies are missing; use --install-deps for non-interactive installation"
  fi
  missing=$(ax_missing_dependencies "$scheduler" "$deployment" || true)
  [[ -z $missing ]] || ax_die "dependencies are still missing: $(tr '\n' ' ' <<<"$missing")"
}

ax_require_root() {
  local interactive=$1
  (( EUID == 0 )) && return 0
  if [[ $interactive == true ]] && ax_command_exists sudo && ax_confirm "Root privileges are required. Re-run through sudo?"; then
    exec sudo --preserve-env=NO_COLOR bash "$0" "${AX_ORIGINAL_ARGS[@]}"
  fi
  ax_die "root privileges are required"
}

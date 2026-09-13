AX_RECOMMENDED_XRAY=26.7.28
AX_XRAY_REPO=XTLS/Xray-core

ax_normalize_version() {
  local value=${1#v}
  [[ $value =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  printf '%s\n' "$value"
}

ax_latest_xray_version() {
  local response version
  response=$(curl --fail --silent --show-error --location --connect-timeout 15 --max-time 45 \
    -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/$AX_XRAY_REPO/releases?per_page=10") || return 1
  version=$(jq -r '[.[] | select(.draft == false)][0].tag_name // empty' <<<"$response")
  ax_normalize_version "$version"
}

ax_installed_xray() {
  local binary=${1:-}
  [[ -n $binary ]] || binary=$(command -v xray 2>/dev/null || true)
  [[ -x $binary ]] || return 1
  local version
  version=$("$binary" version 2>/dev/null | awk 'NR==1 {for(i=1;i<=NF;i++) if ($i ~ /^[v]?[0-9]+\.[0-9]+\.[0-9]+$/) {sub(/^v/,"",$i); print $i; exit}}')
  [[ -n $version ]] || return 1
  printf '%s\t%s\n' "$version" "$binary"
}

ax_resolve_xray_version() {
  local choice=$1 installed
  case $choice in
    recommended) AX_XRAY_VERSION_MODE=recommended; AX_XRAY_VERSION=$AX_RECOMMENDED_XRAY ;;
    latest) AX_XRAY_VERSION_MODE=latest; AX_XRAY_VERSION=$(ax_latest_xray_version) || ax_die "cannot resolve latest Xray release" ;;
    installed)
      AX_XRAY_VERSION_MODE=installed
      if [[ $AX_DEPLOYMENT == host ]]; then
        installed=$(ax_installed_xray) || ax_die "no usable installed Xray binary was found"
        AX_XRAY_VERSION=${installed%%$'\t'*}; AX_XRAY_BIN=${installed#*$'\t'}
      else
        [[ -n ${AX_XRAY_VERSION:-} ]] || ax_die "installed is only available for an existing managed Docker installation"
      fi ;;
    *) AX_XRAY_VERSION_MODE=exact; AX_XRAY_VERSION=$(ax_normalize_version "$choice") || ax_die "invalid Xray version: $choice" ;;
  esac
}

ax_download_xray() {
  local version=$1 tmpdir archive digest expected actual url destination
  tmpdir=$(mktemp -d "$AX_STATE_DIR/.xray-download.XXXXXX")
  archive="$tmpdir/$AX_XRAY_ASSET"; digest="$archive.dgst"
  url="https://github.com/$AX_XRAY_REPO/releases/download/v$version"
  ax_step download "Downloading Xray v$version"
  if ! curl --fail --silent --show-error --location --connect-timeout 15 --max-time 300 --retry 2 \
      --proto '=https' --proto-redir '=https' -o "$archive" "$url/$AX_XRAY_ASSET" ||
     ! curl --fail --silent --show-error --location --connect-timeout 15 --max-time 60 --retry 2 \
      --proto '=https' --proto-redir '=https' -o "$digest" "$url/$AX_XRAY_ASSET.dgst"; then
    rm -rf -- "$tmpdir"; ax_die "cannot download Xray v$version"
  fi
  expected=$(awk -F'= *' '/^SHA2-256=/ {print tolower($2); exit}' "$digest")
  actual=$(sha256sum "$archive" | awk '{print $1}')
  if [[ ! $expected =~ ^[0-9a-f]{64}$ || $actual != "$expected" ]]; then
    rm -rf -- "$tmpdir"; ax_die "Xray archive checksum mismatch"
  fi
  unzip -qq "$archive" xray -d "$tmpdir/unpacked"
  destination="$AX_OPT_DIR/bin/xray-$version"
  install -m 0755 "$tmpdir/unpacked/xray" "$destination"
  rm -rf -- "$tmpdir"
  AX_XRAY_BIN=$destination
}

ax_prepare_xray() {
  if [[ $AX_DEPLOYMENT == docker ]]; then
    AX_XRAY_BIN="ghcr.io/xtls/xray-core:$AX_XRAY_VERSION"
    ax_step pull "Pulling $AX_XRAY_BIN"
    docker pull "$AX_XRAY_BIN" >/dev/null
  elif [[ $AX_XRAY_VERSION_MODE != installed ]]; then
    ax_download_xray "$AX_XRAY_VERSION"
  fi
}

ax_xray_test_config() {
  local config=$1
  if [[ $AX_DEPLOYMENT == docker ]]; then
    docker run --rm -i "$AX_XRAY_BIN" run -test -c stdin: <"$config" >/dev/null 2>&1
  else
    "$AX_XRAY_BIN" run -test -config "$config" >/dev/null 2>&1
  fi
}

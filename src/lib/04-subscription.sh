: "${AX_USER_AGENT:=Happ/auto-xray}"
: "${AX_HEALTH_URLS:=https://cp.cloudflare.com/generate_204 https://www.gstatic.com/generate_204}"

ax_fetch_subscription() {
  local output=$1 headers=$2 url hwid
  [[ -r $AX_SECRET_FILE ]] || ax_die "subscription URL is not configured"
  url=$(<"$AX_SECRET_FILE"); hwid=$(<"$AX_HWID_FILE")
  curl --fail --silent --show-error --location --compressed \
    --connect-timeout 15 --max-time 60 --retry 2 \
    --proto '=https' --proto-redir '=https' \
    --user-agent "$AX_USER_AGENT" \
    --header "x-hwid: $hwid" \
    --header 'x-device-os: Linux' \
    --header "x-ver-os: ${AX_OS_ID:-Linux}-${AX_OS_VERSION:-unknown}" \
    --header 'x-device-model: Server' \
    --dump-header "$headers" --output "$output" "$url"
  chmod 0600 "$output" "$headers"
}

ax_validate_subscription() {
  local file=$1
  jq -e 'type == "array" and length > 0 and all(.[]; type == "object" and (.outbounds | type == "array" and length > 0))' "$file" >/dev/null \
    || ax_die "subscription is not a non-empty Remnawave XRAY_JSON array"
}

ax_subscription_interval() {
  local headers=$1 value
  value=$(awk 'BEGIN{IGNORECASE=1} /^profile-update-interval:[[:space:]]*/ {gsub("\\r",""); sub(/^[^:]+:[[:space:]]*/,""); v=$0} END{print v}' "$headers")
  value=$(ax_trim "$value")
  if [[ $value =~ ^[0-9]+$ ]] && (( value >= 1 && value <= 720 )); then printf '%s\n' "$value"
  else printf '12\n'; fi
}

ax_profile_count() { jq 'length' "$1"; }

ax_profile_remark() {
  local file=$1 index=$2
  jq -r --argjson i "$index" '.[$i].remarks // ("Profile " + (($i + 1) | tostring))' "$file"
}

ax_list_profiles() {
  jq -r 'to_entries[] | "\(.key + 1). \(.value.remarks // ("Profile " + ((.key + 1) | tostring)))"' "$1"
}

ax_extract_profile() {
  local subscription=$1 index=$2 output=$3
  jq --argjson i "$index" '.[$i] | del(.remarks, .meta)' "$subscription" | ax_write_atomic "$output" 0600
}

ax_remark_occurrence() {
  local file=$1 index=$2 remark i occurrence=0
  remark=$(ax_profile_remark "$file" "$index")
  for ((i=0; i<=index; i++)); do
    [[ $(ax_profile_remark "$file" "$i") == "$remark" ]] && ((occurrence+=1))
  done
  printf '%s\n' "$occurrence"
}

ax_find_preferred_index() {
  local file=$1 preferred=$2 occurrence=${3:-1} count i seen=0 remark
  count=$(ax_profile_count "$file")
  for ((i=0; i<count; i++)); do
    remark=$(ax_profile_remark "$file" "$i")
    [[ $remark == "$preferred" ]] || continue
    ((seen+=1))
    if (( seen == occurrence )); then printf '%s\n' "$i"; return 0; fi
  done
  return 1
}

#!/usr/bin/env bash
set -Eeuo pipefail
root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
output=$("$root_dir/dist/auto-xray" --version)
[[ $output == "auto-xray ${VERSION:-dev}" ]]
"$root_dir/dist/auto-xray" --help | grep -q '^Usage:'

source "$root_dir/src/lib/00-common.sh"
source "$root_dir/src/lib/04-subscription.sh"
source "$root_dir/src/lib/05-xray.sh"
fixture="$root_dir/tests/fixtures/subscription.json"
[[ $(ax_profile_count "$fixture") == 3 ]]
[[ $(ax_profile_remark "$fixture" 1) == Working ]]
[[ $(ax_remark_occurrence "$fixture" 2) == 2 ]]
[[ $(ax_find_preferred_index "$fixture" Working 2) == 2 ]]
[[ $(ax_subscription_interval "$root_dir/tests/fixtures/headers.txt") == 6 ]]
tmp_profile=$(mktemp)
ax_extract_profile "$fixture" 1 "$tmp_profile"
jq -e '.remarks == null and .outbounds[0].protocol == "freedom"' "$tmp_profile" >/dev/null
rm -f "$tmp_profile"
[[ $(ax_normalize_version v26.7.28) == 26.7.28 ]]
if ax_normalize_version latest >/dev/null 2>&1; then exit 1; fi

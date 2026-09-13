#!/usr/bin/env bash
set -Eeuo pipefail

version=${1:-dev}
root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
out_dir="$root_dir/dist"
out_file="$out_dir/auto-xray"

mkdir -p "$out_dir"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf 'AUTO_XRAY_VERSION=%q\n' "$version"
  for file in "$root_dir"/src/lib/*.sh; do
    sed '1{/^#!/d;}' "$file"
  done
  sed -e '1{/^#!/d;}' \
      -e '/^# AUTO_XRAY_LIBRARIES$/d' \
      -e '/^if \[\[ -z .*AUTO_XRAY_BUNDLED.*$/,/^fi$/d' \
      "$root_dir/src/auto-xray.sh"
} >"$out_file"
chmod 0755 "$out_file"
(cd "$out_dir" && sha256sum auto-xray >auto-xray.sha256)
printf 'Built %s\n' "$out_file"

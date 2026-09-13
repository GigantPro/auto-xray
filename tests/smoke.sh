#!/usr/bin/env bash
set -Eeuo pipefail
root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
output=$("$root_dir/dist/auto-xray" --version)
[[ $output == "auto-xray ${VERSION:-dev}" ]]
"$root_dir/dist/auto-xray" --help | grep -q '^Usage:'

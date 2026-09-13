#!/usr/bin/env bash
set -Eeuo pipefail
root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

images=(debian:11 debian:12 debian:13 ubuntu:20.04 ubuntu:22.04 ubuntu:24.04 ubuntu:26.04 archlinux:latest)
for image in "${images[@]}"; do
  printf 'Testing %s\n' "$image"
  docker run --rm -v "$root_dir:/work:ro" "$image" bash -lc \
    'cd /work; bash -n dist/auto-xray; dist/auto-xray --version; dist/auto-xray --help >/dev/null'
done

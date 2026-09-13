#!/usr/bin/env bash
# AUTO_XRAY_LIBRARIES
if [[ -z ${AUTO_XRAY_BUNDLED:-} ]]; then
  _ax_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
  for _ax_lib in "$_ax_root"/src/lib/*.sh; do source "$_ax_lib"; done
  unset _ax_root _ax_lib
fi

main() {
  case ${1:-} in
    --version|-V) printf 'auto-xray %s\n' "$AUTO_XRAY_VERSION" ;;
    --help|-h|'') printf 'auto-xray %s\nUsage: auto-xray COMMAND [OPTIONS]\n' "$AUTO_XRAY_VERSION" ;;
    *) ax_die "command not implemented: $1" ;;
  esac
}

main "$@"

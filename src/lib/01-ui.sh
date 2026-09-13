if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
  AX_RED=$'\033[31m'; AX_GREEN=$'\033[32m'; AX_YELLOW=$'\033[33m'
  AX_BLUE=$'\033[34m'; AX_BOLD=$'\033[1m'; AX_DIM=$'\033[2m'; AX_RESET=$'\033[0m'
else
  AX_RED=''; AX_GREEN=''; AX_YELLOW=''; AX_BLUE=''; AX_BOLD=''; AX_DIM=''; AX_RESET=''
fi

ax_info() { printf '%s==>%s %s\n' "$AX_BLUE" "$AX_RESET" "$*"; }
ax_ok() { printf '%sOK%s  %s\n' "$AX_GREEN" "$AX_RESET" "$*"; }
ax_warn() { printf '%sWARN%s %s\n' "$AX_YELLOW" "$AX_RESET" "$*" >&2; }
ax_error() { printf '%sERROR%s %s\n' "$AX_RED" "$AX_RESET" "$*" >&2; }

ax_confirm() {
  local prompt=$1 default=${2:-no} answer suffix='[y/N]'
  [[ $default == yes ]] && suffix='[Y/n]'
  read -r -p "$prompt $suffix " answer
  answer=${answer:-$default}
  [[ ${answer,,} == y || ${answer,,} == yes ]]
}

ax_prompt() {
  local prompt=$1 default=${2:-} secret=${3:-false} value
  if [[ $secret == true ]]; then read -r -s -p "$prompt: " value; printf '\n' >&2
  else read -r -p "$prompt${default:+ [$default]}: " value
  fi
  printf '%s\n' "${value:-$default}"
}

ax_select() {
  local prompt=$1; shift
  local -a options=("$@")
  local index=0 key='' count=${#options[@]} i
  (( count > 0 )) || return 1
  if [[ ! -t 0 || ! -t 1 ]]; then ax_die "interactive selection requires a TTY"; fi
  printf '%s%s%s\n' "$AX_BOLD" "$prompt" "$AX_RESET" >&2
  while true; do
    for ((i=0; i<count; i++)); do
      if (( i == index )); then printf '  %s❯ %s%s\n' "$AX_GREEN" "${options[i]}" "$AX_RESET" >&2
      else printf '    %s\n' "${options[i]}" >&2
      fi
    done
    IFS= read -rsn1 key
    if [[ $key == $'\e' ]]; then read -rsn2 -t 0.1 key || true; fi
    case $key in
      '[A') (( index = (index - 1 + count) % count )) ;;
      '[B') (( index = (index + 1) % count )) ;;
      '') printf '%s\n' "$index"; return 0 ;;
      q|Q) return 1 ;;
      *) continue ;;
    esac
    printf '\033[%dA' "$count" >&2
  done
}

ax_step() { printf '%s[%s]%s %s\n' "$AX_DIM" "$1" "$AX_RESET" "$2"; }

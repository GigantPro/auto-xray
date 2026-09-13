#!/usr/bin/env bats

setup() {
  export PROJECT_ROOT="$BATS_TEST_DIRNAME/.."
  export AX_ETC_DIR="$BATS_TEST_TMPDIR/etc"
  export AX_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export AX_LOG_DIR="$BATS_TEST_TMPDIR/log"
  export AX_OPT_DIR="$BATS_TEST_TMPDIR/opt"
  export AX_BIN_LINK="$BATS_TEST_TMPDIR/bin/auto-xray"
  source "$PROJECT_ROOT/src/lib/00-common.sh"
  source "$PROJECT_ROOT/src/lib/03-state.sh"
  source "$PROJECT_ROOT/src/lib/04-subscription.sh"
  source "$PROJECT_ROOT/src/lib/07-update.sh"
}

@test "validates Remnawave XRAY_JSON arrays" {
  ax_validate_subscription "$PROJECT_ROOT/tests/fixtures/subscription.json"
  printf '%s\n' '{}' >"$BATS_TEST_TMPDIR/invalid.json"
  run ax_validate_subscription "$BATS_TEST_TMPDIR/invalid.json"
  [ "$status" -ne 0 ]
}

@test "parses interval and profile identity" {
  [ "$(ax_subscription_interval "$PROJECT_ROOT/tests/fixtures/headers.txt")" = 6 ]
  [ "$(ax_find_preferred_index "$PROJECT_ROOT/tests/fixtures/subscription.json" Working 2)" = 2 ]
}

@test "orders preferred first and then every remaining profile" {
  run ax_candidate_order "$PROJECT_ROOT/tests/fixtures/subscription.json" 1
  [ "$status" -eq 0 ]
  [ "$output" = $'1\n0\n2' ]
}

@test "stores subscription URL and HWID with private permissions" {
  ax_init_directories
  ax_save_subscription_url 'https://example.invalid/secret-token'
  ax_ensure_hwid
  [ "$(stat -c %a "$AX_SECRET_FILE")" = 600 ]
  [ "$(stat -c %a "$AX_HWID_FILE")" = 600 ]
  [[ $(<"$AX_HWID_FILE") =~ ^[A-Za-z0-9=-]{10,64}$ ]]
}

@test "built CLI rejects unknown commands" {
  run "$PROJECT_ROOT/dist/auto-xray" unknown
  [ "$status" -ne 0 ]
  [[ $output == *"unknown command"* ]]
}

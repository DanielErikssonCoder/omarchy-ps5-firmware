#!/usr/bin/env bash
# The plugin's test suite.
#
# Every case runs the real command against a stored manifest and asserts what it
# wrote, so nothing here tests a copy of the logic: the fixtures are real
# replies from the API plus edits that change exactly one thing each
# (see tests/fixtures/README.md).
#
#   ./tests/run.sh
#
# Exit 0 = every case passed. Exit 1 = at least one failed, and the failing
# filter is printed so the failure can be reproduced by hand.
set -uo pipefail

TESTS_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PLUGIN_DIR=$(cd -- "$TESTS_DIR/.." && pwd)
CLI="$PLUGIN_DIR/bin/ps5-firmware"
FIX="$TESTS_DIR/fixtures"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The suite never touches the desktop it runs on. Every send goes to the
# stand-in in tests/support, which records the call and answers like the real
# tool does; the notification section below asserts that log.
export PS5_NOTIFY_SEND="$TESTS_DIR/support/fake-notify.sh"
export PS5_NOTIFY_LOG="$WORK/notify.log"
: >"$PS5_NOTIFY_LOG"

notify_calls() { wc -l <"$PS5_NOTIFY_LOG" | tr -d ' '; }
notify_line() { sed -n "${1}p" "$PS5_NOTIFY_LOG"; }

says() {
  # says <name> <line number> <substring>
  if [[ $(notify_line "$2") == *"$3"* ]]; then ok "$1"; else
    fail=$((fail + 1))
    printf '  FAIL  %s\n        wanted %s in: %s\n' "$1" "$3" "$(notify_line "$2")"
  fi
}

does_not_say() {
  if [[ $(notify_line "$2") != *"$3"* ]]; then ok "$1"; else
    fail=$((fail + 1))
    printf '  FAIL  %s\n        did not want %s in: %s\n' "$1" "$3" "$(notify_line "$2")"
  fi
}

counts() {
  # counts <name> <expected>
  if [[ $(notify_calls) == "$2" ]]; then ok "$1"; else
    fail=$((fail + 1))
    printf '  FAIL  %s\n        expected %s send(s), got %s\n' "$1" "$2" "$(notify_calls)"
  fi
}

pass=0
fail=0

ok() {
  pass=$((pass + 1))
  printf '  ok    %s\n' "$1"
}

bad() {
  fail=$((fail + 1))
  printf '  FAIL  %s\n        filter: %s\n' "$1" "$2"
  [[ -f ${3:-} ]] && jq -c '{sourceOk, failsInARow, view: (.view // null), baseline: (.baseline // null), events: (.events // null), notify: (.notify // null)}' "$3" 2>/dev/null | sed 's/^/        state:  /'
}

# run <state file> <now> <fixture> [extra args...]
run() {
  local state="$1" now="$2" fixture="$3"
  shift 3
  "$CLI" --once --quiet --json --state "$state" --now "$now" --source "$fixture" "$@" >/dev/null 2>&1
}

# assert <name> <jq filter> <file>
assert() {
  if jq -e "$2" "$3" >/dev/null 2>&1; then ok "$1"; else bad "$1" "$2" "$3"; fi
}

# expect_exit <name> <expected code> <command...>
expect_exit() {
  local name="$1" want="$2"
  shift 2
  "$@" >/dev/null 2>&1
  local got=$?
  if [[ $got == "$want" ]]; then ok "$name"; else
    fail=$((fail + 1))
    printf '  FAIL  %s\n        expected exit %s, got %s\n' "$name" "$want" "$got"
  fi
}

BASE="$FIX/manifest-2026-09-25.json"
LATEST="$FIX/manifest-latest-15.00.json"
MINIMUM="$FIX/manifest-minimum-14.00.json"
REBUILT="$FIX/manifest-rebuilt.json"
REGION_DOWN="$FIX/manifest-region-down.json"

echo "baseline and silence"
S="$WORK/a/state.json"
run "$S" 2026-09-25T10:00:00Z "$BASE"
assert "first run records no change at all" '.events == [] and .notify == null' "$S"
assert "first run starts the baseline clock" '.baseline.latest.since == "2026-09-25T10:00:00Z"' "$S"
run "$S" 2026-09-25T10:30:00Z "$BASE"
assert "an identical reading still says nothing" '.events == [] and .notify == null and .checks == 2' "$S"
assert "an unchanged value keeps its original since" '.baseline.latest.since == "2026-09-25T10:00:00Z"' "$S"
assert "the reading is kept whole" '.view.latest == "14.00" and .view.minimum == "13.60"' "$S"

echo "a new latest version"
run "$S" 2026-09-25T11:00:00Z "$LATEST"
assert "the version change is an event" '[.events[] | select(.kind == "latest")] | length == 1' "$S"
assert "the notification names the new version" '.notify.headline == "PS5 firmware 15.00"' "$S"
assert "the change resets the baseline clock" '.baseline.latest.since == "2026-09-25T11:00:00Z"' "$S"
assert "the body shows the move" '.notify.body | startswith("Latest 14.00 → 15.00")' "$S"
run "$S" 2026-09-25T11:30:00Z "$LATEST"
assert "the same news is not announced twice" '.notify == null' "$S"
assert "the old announcement is remembered" '.notified.key != ""' "$S"

echo "a raised minimum"
S="$WORK/b/state.json"
run "$S" 2026-09-25T10:00:00Z "$BASE"
run "$S" 2026-09-25T10:30:00Z "$MINIMUM"
assert "only the minimum moves" '.events as $e
  | ([$e[] | select(.kind == "minimum")] | length) == 1
    and ([$e[] | select(.kind == "latest")] | length) == 0' "$S"
assert "the notification says it is the minimum" '.notify.headline == "PS5 minimum raised to 14.00"' "$S"

echo "the same version, a rebuilt image"
S="$WORK/c/state.json"
run "$S" 2026-09-25T10:00:00Z "$BASE"
run "$S" 2026-09-25T10:30:00Z "$REBUILT"
assert "a new build hash is its own event" '[.events[] | select(.kind == "build")] | length == 1' "$S"
assert "the version itself is unchanged" '.view.latest == "14.00"' "$S"
assert "the notification says rebuilt" '.notify.headline == "PS5 firmware image rebuilt"' "$S"

echo "a region losing coverage"
S="$WORK/d/state.json"
run "$S" 2026-09-25T10:00:00Z "$BASE"
run "$S" 2026-09-25T10:30:00Z "$REGION_DOWN"
assert "the region change is recorded" '[.events[] | select(.scope == "us" and .kind == "coverage")] | length == 1' "$S"
assert "an unwatched region does not notify" '.notify == null' "$S"
assert "the aggregate keeps its own count" '.view.readable == 7' "$S"
S="$WORK/d2/state.json"
run "$S" 2026-09-25T10:00:00Z "$BASE" --region us
run "$S" 2026-09-25T10:30:00Z "$REGION_DOWN" --region us
assert "the watched region does notify" '.notify.headline == "PS5 region us is no longer readable"' "$S"
assert "the watched view follows the region" '.view.code == "us" and .view.status == "UNAVAILABLE"' "$S"
run "$S" 2026-09-25T11:00:00Z "$BASE" --region us
assert "recovery is reported too" '[.events[] | select(.kind == "coverage" and .to == "LIVE")] | length == 1' "$S"

echo "the source stops answering"
S="$WORK/e/state.json"
run "$S" 2026-09-25T10:00:00Z "$BASE"
for n in 1 2 3; do
  run "$S" "2026-09-25T10:0${n}:00Z" "$WORK/does-not-exist.json"
done
assert "three failures are counted" '.sourceOk == false and .failsInARow == 3' "$S"
assert "three failures stay quiet" '.notify == null' "$S"
run "$S" 2026-09-25T10:04:00Z "$WORK/does-not-exist.json"
assert "the fourth failure is announced" '.notify.headline == "PS5 firmware source is not answering"' "$S"
assert "the last good reading survives" '.view.latest == "14.00" and .reading.source.health == "PARTIAL"' "$S"
assert "the reason is recorded" '.lastError != null' "$S"
run "$S" 2026-09-25T10:05:00Z "$BASE"
assert "a good run clears the failure count" '.sourceOk == true and .failsInARow == 0' "$S"
run "$S" 2026-09-25T10:06:00Z "$BASE"
assert "the recovered reading is not announced as news" '.notify == null' "$S"

echo "the notification reaches the desktop"
: >"$PS5_NOTIFY_LOG"
S="$WORK/n/state.json"
run "$S" 2026-09-25T10:00:00Z "$BASE"
counts "a first reading says nothing to the desktop" 0
run "$S" 2026-09-25T10:30:00Z "$LATEST"
counts "a new version is announced once" 1
says "the toast carries the headline" 1 "PS5 firmware 15.00"
says "a firmware release is a normal toast, not a whisper" 1 "-u normal"
does_not_say "the first toast opens its own bubble" 1 "-r "
assert "the send is recorded as delivered" '.notified.key != "" and .notifyError == null' "$S"
run "$S" 2026-09-25T11:00:00Z "$LATEST"
counts "a re-check of the same news sends nothing" 1
run "$S" 2026-09-25T11:30:00Z "$REBUILT"
counts "the next change is announced too" 2
says "it updates the same bubble instead of stacking a new one" 2 "-r 1001"

echo "a toast that never reached the screen"
: >"$PS5_NOTIFY_LOG"
S="$WORK/n2/state.json"
run "$S" 2026-09-25T10:00:00Z "$BASE"
export PS5_NOTIFY_FAIL=1
run "$S" 2026-09-25T10:30:00Z "$LATEST"
unset PS5_NOTIFY_FAIL
assert "the news stays pending when the toast fails" '.notify != null and .notified.key == ""' "$S"
assert "the failed send is recorded" '.notifyError != null' "$S"
run "$S" 2026-09-25T11:00:00Z "$LATEST"
assert "the next run delivers what it kept" '.notified.key != "" and .notifyError == null' "$S"
counts "the retry reached the desktop" 2

# A pending source-down notice is a fact about a moment that has passed: once the
# source answers again, telling him it is down would be wrong.
echo "a pending notice that is no longer true"
: >"$PS5_NOTIFY_LOG"
S="$WORK/n4/state.json"
run "$S" 2026-09-25T10:00:00Z "$BASE"
export PS5_NOTIFY_FAIL=1
for n in 1 2 3 4; do
  run "$S" "2026-09-25T10:0${n}:00Z" "$WORK/does-not-exist.json"
done
assert "the pending source-down notice is kept while it is true" \
  '.notify.key == "source-down:4"' "$S"
run "$S" 2026-09-25T10:05:00Z "$BASE"
unset PS5_NOTIFY_FAIL
assert "a recovered source drops the pending notice" '.notify == null' "$S"

echo "recording is not the same as announcing"
: >"$PS5_NOTIFY_LOG"
S="$WORK/n3/state.json"
run "$S" 2026-09-25T10:00:00Z "$BASE"
run "$S" 2026-09-25T10:30:00Z "$LATEST" --no-notify
assert "--no-notify still records what changed" '.notify != null and .notified.key == ""' "$S"
counts "--no-notify sends nothing" 0

echo "the plugin's settings live in shell.json"
mkdir -p "$WORK/xdg/omarchy"
printf '%s' '{"bar":{"layout":{"right":[{"id":"io.github.danielerikssoncoder.ps5-firmware","region":"us"}]}}}' \
  >"$WORK/xdg/omarchy/shell.json"
S="$WORK/h/state.json"
XDG_CONFIG_HOME="$WORK/xdg" "$CLI" --once --quiet --json --state "$S" --now 2026-09-25T10:00:00Z \
  --source "$BASE" >/dev/null 2>&1
assert "the widget's own region setting decides the scope" '.region == "us"' "$S"
XDG_CONFIG_HOME="$WORK/xdg" "$CLI" --once --quiet --json --state "$S" --now 2026-09-25T10:01:00Z \
  --source "$BASE" --region GLOBAL >/dev/null 2>&1
assert "an explicit --region still wins" '.region == "GLOBAL"' "$S"

# A reply may cost at most 1 MiB, and that is a limit on bytes written rather
# than on time: this source announces no size, so without a cap a fast server
# could fill the disk long before a 20 second timeout fires. Raised by the
# marketplace review, which is why all three routes are covered here.
echo "a reply that is too large"
S="$WORK/s/state.json"
run "$S" 2026-09-25T10:00:00Z "$BASE"
head -c 2097152 /dev/zero >"$WORK/huge.json"
run "$S" 2026-09-25T10:30:00Z "$WORK/huge.json"
assert "a local source past the limit is refused" '.sourceOk == false and .failsInARow == 1' "$S"
assert "the reason names the limit" '.lastError | test("larger than 1048576 bytes")' "$S"
assert "the last good reading survives a refused reply" '.view.latest == "14.00"' "$S"

if command -v python3 >/dev/null 2>&1; then
  python3 "$TESTS_DIR/support/huge-server.py" "$WORK/port" >/dev/null 2>&1 &
  SERVER_PID=$!
  for _ in $(seq 60); do [[ -s $WORK/port ]] && break; sleep 0.1; done
  PORT=$(cat "$WORK/port" 2>/dev/null || true)
  if [[ -n $PORT ]]; then
    run "$S" 2026-09-25T10:31:00Z "http://127.0.0.1:$PORT/declared"
    assert "a reply that announces 512 MiB is refused" \
      '.lastError | test("larger than 1048576 bytes")' "$S"
    run "$S" 2026-09-25T10:32:00Z "http://127.0.0.1:$PORT/stream"
    assert "a reply that announces no size is cut at the limit" \
      '.lastError | test("larger than 1048576 bytes")' "$S"
    run "$S" 2026-09-25T10:33:00Z "$BASE"
    assert "a good reply after a refused one clears the failure" \
      '.sourceOk == true and .failsInARow == 0' "$S"
  else
    printf '  skip  the HTTP size cases (the stand-in server did not start)\n'
  fi
  kill "$SERVER_PID" 2>/dev/null
  wait "$SERVER_PID" 2>/dev/null
else
  printf '  skip  the HTTP size cases (python3 is not installed)\n'
fi

echo "the interface"
S="$WORK/f/state.json"
run "$S" 2026-09-25T10:00:00Z "$BASE"
"$CLI" --print --state "$S" >"$WORK/print.json" 2>/dev/null
assert "--print writes the state" '.view.latest == "14.00"' "$WORK/print.json"
expect_exit "an unknown argument is a usage error" 2 "$CLI" --nonsense
expect_exit "an impossible region is a usage error" 2 "$CLI" --once --region SWEDEN
expect_exit "--print without a state file is a usage error" 2 "$CLI" --print --state "$WORK/nothing-here.json"
expect_exit "a missing source file is not a crash" 0 "$CLI" --once --quiet --state "$WORK/g/state.json" --source "$WORK/nope.json"
assert "a missing source leaves a failure state" '.sourceOk == false and .failsInARow == 1' "$WORK/g/state.json"

echo
printf '%s passed, %s failed\n' "$pass" "$fail"
[[ $fail == 0 ]]

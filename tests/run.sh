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

# A redirect is a hop out of the host the settings named, and its target is
# chosen by whoever answers: a redirected check can be pointed at a plain HTTP
# address on this machine or on the local network. The plugin therefore follows
# none of them. Raised by the marketplace review, and the stand-in below records
# every request it receives, so this asserts which addresses were contacted and
# not only which flags curl was given.
echo "a source that answers with a redirect"
if command -v python3 >/dev/null 2>&1; then
  : >"$WORK/redirect.log"
  python3 "$TESTS_DIR/support/redirect-server.py" "$WORK/rport" "$BASE" "$WORK/redirect.log" \
    >/dev/null 2>&1 &
  RPID=$!
  for _ in $(seq 60); do [[ -s $WORK/rport ]] && break; sleep 0.1; done
  PORT=$(cat "$WORK/rport" 2>/dev/null || true)
  if [[ -n $PORT ]]; then
    S="$WORK/r/state.json"
    run "$S" 2026-09-25T10:00:00Z "$BASE"
    run "$S" 2026-09-25T10:30:00Z "http://127.0.0.1:$PORT/local"
    assert "a redirect to a local http address is refused" \
      '.sourceOk == false and .failsInARow == 1' "$S"
    assert "the reason is ours and says what to do instead" \
      '.lastError | test("answered with a redirect.*final https address")' "$S"
    assert "the last good reading survives a refused redirect" '.view.latest == "14.00"' "$S"
    contacted=$(tr '\n' ' ' <"$WORK/redirect.log")
    if [[ $contacted == "/local " ]]; then
      ok "the redirect target was never contacted"
    else
      fail=$((fail + 1))
      printf '  FAIL  %s\n        paths requested: %s\n' \
        "the redirect target was never contacted" "${contacted:-none}"
    fi
    run "$S" 2026-09-25T10:31:00Z "http://127.0.0.1:$PORT/elsewhere"
    assert "a redirect to another host is refused too" \
      '.lastError | test("answered with a redirect")' "$S"
    run "$S" 2026-09-25T10:32:00Z "http://127.0.0.1:$PORT/manifest"
    assert "a source that answers directly is still read" \
      '.sourceOk == true and .failsInARow == 0 and .view.latest == "14.00"' "$S"
  else
    printf '  skip  the redirect cases (the stand-in server did not start)\n'
  fi
  kill "$RPID" 2>/dev/null
  wait "$RPID" 2>/dev/null
else
  printf '  skip  the redirect cases (python3 is not installed)\n'
fi

# Sony shut the aggregator this plugin used to read (psn.etawen.lol) down on
# 2026-09-29, so the plugin now reads Sony's own regional lists itself: over
# https, against the Sony root certificate that travels with it. The stand-in
# below holds one file per region and answers 404 for the rest, which is what the
# real hosts do: eight of the thirteen regions have a list, five do not.
echo "the source is Sony's own regional lists"

SONY_FIX="$FIX/sony"

sony_start() {  # sony_start <directory with one <code>.xml per region>
  : >"$WORK/sony.log"
  # The port file is written by the server, so an earlier server's file has to go
  # first: a leftover would be read as this server's port and every region would
  # look unreachable.
  rm -f "$WORK/sonyport"
  python3 "$TESTS_DIR/support/sony-server.py" "$WORK/sonyport" "$1" "$WORK/sony.log" \
    >/dev/null 2>&1 &
  SONYPID=$!
  for _ in $(seq 60); do [[ -s $WORK/sonyport ]] && break; sleep 0.1; done
  local port
  port=$(cat "$WORK/sonyport" 2>/dev/null || echo 0)
  PS5_SONY_BASE="http://127.0.0.1:$port"
  export PS5_SONY_BASE
}

sony_stop() {
  kill "$SONYPID" 2>/dev/null
  wait "$SONYPID" 2>/dev/null
  unset PS5_SONY_BASE
}

# sony_run <state> <now> [extra...]: the check as it runs on the desktop, with no
# --source at all.
sony_run() {
  local state=$1 now=$2
  shift 2
  "$CLI" --once --quiet --json --state "$state" --now "$now" "$@" >/dev/null 2>&1
}

# sony_reason <curl exit> <stderr file>: our own words for a region that failed.
sony_reason_of() {
  bash -c 'set -euo pipefail; PLUGIN_DIR=$1; LIB_DIR=$1/lib; SOURCE_MAX_BYTES=1048576
           SOURCE_TIMEOUT=20; source "$1/lib/sony.sh"; sony_reason "$2" "${3:-/dev/null}" 0' \
    _ "$PLUGIN_DIR" "$1" "${2:-}" 2>/dev/null || true
}

if command -v python3 >/dev/null 2>&1 && command -v xmllint >/dev/null 2>&1; then
  mkdir -p "$WORK/sony-a" "$WORK/sony-b" "$WORK/sony-c" "$WORK/sony-d" "$WORK/sony-empty"
  cp "$SONY_FIX/updatelist-us-14.00.xml" "$WORK/sony-a/us.xml"
  cp "$SONY_FIX/updatelist-jp-14.00.xml" "$WORK/sony-a/jp.xml"
  cp "$SONY_FIX/updatelist-us-15.00.xml" "$WORK/sony-b/us.xml"
  cp "$SONY_FIX/updatelist-jp-14.00.xml" "$WORK/sony-b/jp.xml"
  cp "$SONY_FIX/updatelist-us-14.00.xml" "$WORK/sony-c/us.xml"
  cp "$SONY_FIX/updatelist-us-14.00.xml" "$WORK/sony-c/jp.xml"   # jp gets the US list
  cp "$SONY_FIX/not-a-list.txt" "$WORK/sony-d/us.xml"

  sony_start "$WORK/sony-a"
  S="$WORK/sony-state/state.json"
  sony_run "$S" 2026-09-29T10:00:00Z
  assert "the reading says it came from Sony" \
    '.sourceOk == true and .reading.source.name == "Sony"' "$S"
  assert "the regions that answered are the live ones" \
    '[.reading.regions[] | select(.status == "LIVE")] | length == 2' "$S"
  assert "the global figure is the one they agree on" \
    '.reading.global.latest == "14.00" and .reading.global.minimum == "13.60"
     and .reading.global.agree == 2' "$S"
  assert "the regions without a list are still counted" \
    '.reading.global.available == 2 and .reading.global.total == 13' "$S"
  assert "a region without a list says why, in our words" \
    'any(.reading.regions[]; .code == "eu" and .error == "HTTP 404")' "$S"
  assert "the build hash still comes out of the image path" \
    '.view.buildHash | startswith("1eb4b184")' "$S"
  asked=$(wc -l <"$WORK/sony.log" | tr -d ' ')
  if [[ $asked == 13 ]]; then
    ok "each region is asked once per check"
  else
    fail=$((fail + 1))
    printf '  FAIL  %s\n        asked %s times, wanted 13\n' \
      "each region is asked once per check" "$asked"
  fi
  sony_run "$S" 2026-09-29T10:30:00Z --region jp
  assert "the region setting still scopes the reading" \
    '.view.code == "jp" and .view.latest == "14.00"' "$S"
  sony_stop

  echo "a region that has not caught up"
  sony_start "$WORK/sony-b"
  S="$WORK/sony-b-state/state.json"
  sony_run "$S" 2026-09-29T10:00:00Z
  assert "one region ahead moves the global figure" '.reading.global.latest == "15.00"' "$S"
  assert "a disagreement is reported as a disagreement" \
    '.reading.global.agree == 1 and .reading.global.available == 2
     and .view.status == "PARTIAL"' "$S"
  sony_stop

  echo "a list that belongs to another region"
  sony_start "$WORK/sony-c"
  S="$WORK/sony-c-state/state.json"
  sony_run "$S" 2026-09-29T10:00:00Z
  assert "another region's list is not read as this one's" \
    'any(.reading.regions[]; .code == "jp" and .status == "UNAVAILABLE")' "$S"
  assert "the region with its own list is still read" \
    'any(.reading.regions[]; .code == "us" and .status == "LIVE")' "$S"
  sony_stop

  echo "a reply that is not a list at all"
  sony_start "$WORK/sony-d"
  S="$WORK/sony-d-state/state.json"
  sony_run "$S" 2026-09-29T10:00:00Z
  assert "a reply that is not a list is refused" '.sourceOk == false' "$S"
  assert "the reason says how many lists answered" \
    '.lastError | test("none of the 13 regional lists answered")' "$S"
  sony_stop

  echo "no region answering at all"
  S="$WORK/sony-kept/state.json"
  sony_start "$WORK/sony-a"
  sony_run "$S" 2026-09-29T10:00:00Z
  sony_stop
  sony_start "$WORK/sony-empty"
  sony_run "$S" 2026-09-29T10:30:00Z
  assert "a source that answers nothing is recorded as down" \
    '.sourceOk == false and .failsInARow == 1' "$S"
  assert "the last good reading survives it" \
    '.view.latest == "14.00" and .reading.source.health == "PARTIAL"' "$S"
  sony_stop

  # The tool that noticed is not the thing a reader should have to interpret.
  for pair in "6:the host did not resolve" "28:the reply did not finish in 20 seconds" \
    "60:the certificate did not verify against the Sony root the plugin carries"; do
    code=${pair%%:*}
    want=${pair#*:}
    got=$(sony_reason_of "$code")
    if [[ $got == "$want" ]]; then
      ok "a region that failed is explained in our words (curl $code)"
    else
      fail=$((fail + 1))
      printf '  FAIL  %s\n        wanted %s, got %s\n' \
        "a region that failed is explained in our words (curl $code)" "$want" "${got:-nothing}"
    fi
  done
  printf 'curl: (22) The requested URL returned error: 404\n' >"$WORK/sony-404.err"
  got=$(sony_reason_of 22 "$WORK/sony-404.err")
  if [[ $got == "HTTP 404" ]]; then
    ok "the http status is read out of curl's line, not guessed"
  else
    fail=$((fail + 1))
    printf '  FAIL  %s\n        wanted HTTP 404, got %s\n' \
      "the http status is read out of curl's line, not guessed" "${got:-nothing}"
  fi

  # The anchor is the exact certificate the https path was measured against. A
  # different file changes what this plugin trusts, so replacing it has to be a
  # deliberate, visible change rather than a quiet one.
  if [[ $(sha256sum "$PLUGIN_DIR/assets/scei-dnas-root-05.pem" | cut -d' ' -f1) \
        == "1822b8906539482c181577f9d9321bba711038ba5e3431447f0dcd7683733d0f" ]]; then
    ok "the pinned Sony root is the certificate this was measured against"
  else
    fail=$((fail + 1))
    printf '  FAIL  %s\n' "the pinned Sony root is not the certificate this was measured against"
  fi
  if grep -qF -- "--proto '=https'" "$PLUGIN_DIR/lib/sony.sh" \
    && grep -qF -- '--cacert "$SONY_CA"' "$PLUGIN_DIR/lib/sony.sh" \
    && grep -qF -- '--max-redirs 0' "$PLUGIN_DIR/lib/sony.sh"; then
    ok "the Sony read is https only, pinned, and follows no redirect"
  else
    fail=$((fail + 1))
    printf '  FAIL  %s\n' "the Sony read no longer insists on https and the pinned root"
  fi
  if grep -rn 'psn\.etawen\.lol' "$PLUGIN_DIR/bin" "$PLUGIN_DIR/lib" "$PLUGIN_DIR"/*.qml \
      >/dev/null 2>&1; then
    fail=$((fail + 1))
    printf '  FAIL  %s\n' "the plugin still asks the aggregator that was shut down"
  else
    ok "nothing asks the aggregator that was shut down"
  fi
  if grep -q "Sony's own update lists" "$PLUGIN_DIR/Panel.qml"; then
    ok "the panel says where the numbers come from"
  else
    fail=$((fail + 1))
    printf '  FAIL  %s\n' "the panel does not say where the numbers come from"
  fi
else
  printf '  skip  the Sony cases (python3 or xmllint is missing)\n'
fi

# The state file is the plugin's own, but it is read by path, so a path that has
# been replaced by something else must not be able to hold the check up, or to be
# read without a bound. Raised by the marketplace review: a substituted FIFO can
# stall a scheduled check, an oversized file can exhaust memory, and notify.id was
# written straight over whatever the name pointed at.
echo "the state file is read as a plain, bounded file"
HARD="$WORK/hardening"
mkdir -p "$HARD"
S="$HARD/state.json"
run "$S" 2026-09-29T10:00:00Z "$BASE"
if [[ -f $S && ! -L $S ]]; then
  ok "the first run writes a plain state file"
else
  fail=$((fail + 1))
  printf '  FAIL  %s\n' "the first run writes a plain state file"
fi

# A link where the state belongs is not a previous reading, and the run must
# replace the link rather than write through it.
cp "$S" "$HARD/elsewhere.json"
cp "$S" "$HARD/elsewhere.expected.json"
rm -f "$S"
ln -s "$HARD/elsewhere.json" "$S"
expect_exit "--print refuses a state file that is a link" 2 "$CLI" --print --state "$S"
run "$S" 2026-09-29T11:00:00Z "$LATEST"
if [[ -f $S && ! -L $S ]]; then
  ok "a run replaces a linked state path instead of writing through it"
else
  fail=$((fail + 1))
  printf '  FAIL  %s\n' "a run replaces a linked state path instead of writing through it"
fi
if cmp -s "$HARD/elsewhere.json" "$HARD/elsewhere.expected.json"; then
  ok "the file the link pointed at is left untouched"
else
  fail=$((fail + 1))
  printf '  FAIL  %s\n' "the file the link pointed at is left untouched"
fi
assert "a refused link counts as no previous reading" '.checks == 1 and .events == []' "$S"

# A FIFO in that place must not make the scheduled check wait for a writer. The
# service always passes --if-stale, and that is the read a FIFO would stall.
rm -f "$S"
mkfifo "$S"
start=$(date +%s)
timeout 20 "$CLI" --once --quiet --json --state "$S" --now 2026-09-29T12:00:00Z \
  --source "$BASE" --if-stale 3600 >/dev/null 2>&1
rc=$?
elapsed=$(( $(date +%s) - start ))
if [[ $rc == 0 && $elapsed -lt 10 ]]; then
  ok "a FIFO in the state path does not stall the check"
else
  fail=$((fail + 1))
  printf '  FAIL  %s\n        exit %s after %ss\n' \
    "a FIFO in the state path does not stall the check" "$rc" "$elapsed"
fi
if [[ -f $S && ! -p $S ]]; then
  ok "the run replaces the FIFO with a real file"
else
  fail=$((fail + 1))
  printf '  FAIL  %s\n' "the run replaces the FIFO with a real file"
fi

# A state file past the cap is refused rather than slurped. The file is made
# fresh on purpose: if it were read, --if-stale would skip the check, so a state
# carrying this run's own timestamp is the proof that it was refused.
rm -f "$S"
NOWREAL=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -c --arg now "$NOWREAL" '.takenAt = $now | . + {filler: ("x" * 1200000)}' \
  "$HARD/elsewhere.json" >"$S"
if [[ $(stat -c %s "$S") -gt 1048576 ]]; then
  ok "the oversized case really is larger than the cap"
else
  fail=$((fail + 1))
  printf '  FAIL  %s\n' "the oversized case really is larger than the cap"
fi
"$CLI" --once --quiet --json --state "$S" --now 2026-09-29T13:00:00Z --source "$BASE" \
  --if-stale 3600 >/dev/null 2>&1
assert "a state file past the cap is refused, so the check runs" \
  '.takenAt == "2026-09-29T13:00:00Z"' "$S"
assert "and the run started from scratch instead of trusting it" \
  '.sourceOk == true and .checks == 1' "$S"

# The id of the bubble that is being updated is read and written the same way.
# Its own directory, so nothing earlier in the suite has left an id file there.
mkdir -p "$HARD/notify"
S="$HARD/notify/state.json"
run "$S" 2026-09-29T10:00:00Z "$BASE"
printf 'original\n' >"$HARD/notify/keep-target"
ln -s "$HARD/notify/keep-target" "$HARD/notify/notify.id"
if [[ -L $HARD/notify/notify.id ]]; then
  ok "the notify.id case starts with a link in place"
else
  fail=$((fail + 1))
  printf '  FAIL  %s\n' "the notify.id case starts with a link in place"
fi
: >"$PS5_NOTIFY_LOG"
run "$S" 2026-09-29T10:30:00Z "$LATEST"
counts "a change is still announced with a link at notify.id" 1
if [[ -f $HARD/notify/notify.id && ! -L $HARD/notify/notify.id ]]; then
  ok "the id is written to a real file, not through the link"
else
  fail=$((fail + 1))
  printf '  FAIL  %s\n' "the id is written to a real file, not through the link"
fi
if [[ $(cat "$HARD/notify/keep-target" 2>/dev/null) == "original" ]]; then
  ok "the file that link pointed at is left untouched"
else
  fail=$((fail + 1))
  printf '  FAIL  %s\n' "the file that link pointed at is left untouched"
fi

# Qt's default textFormat is AutoText, which reads a string as HTML. The panel
# renders strings that come from the source, so a manifest carrying
# <img src="http://..."> would make the panel try to fetch that URL. Every Text
# element therefore states PlainText, and this case keeps it that way: measured
# with qml6 against a local listener, AutoText (and the default) requested the
# URL while PlainText did not.
echo "text from the source is never read as markup"
for f in "$PLUGIN_DIR"/*.qml; do
  total=$(grep -o -e 'Text {' -e 'Label {' "$f" | wc -l | tr -d ' ')
  plain=$(grep -c 'textFormat: Text.PlainText' "$f" || true)
  if [[ $total == "$plain" ]]; then
    ok "$(basename "$f"): all $total text elements are plain text"
  else
    fail=$((fail + 1))
    printf '  FAIL  %s\n        %s text elements, %s set PlainText\n' "$(basename "$f")" "$total" "$plain"
  fi
done

# The download link comes from the manifest, so it can contain anything. The copy
# path therefore hands it to wl-copy as one argument through the shell's own argv
# runner (`exec "$@"`) instead of building a shell string, where quoting could be
# got wrong. The behavioural half below runs that same shape with a hostile link
# and checks it arrives untouched.
echo "a copied link is data, not a command"
if grep -q 'Util.execArgv(\["wl-copy", "--", value\])' "$PLUGIN_DIR/Panel.qml"; then
  ok "the link is handed to wl-copy as an argument, not through a shell"
else
  fail=$((fail + 1))
  printf '  FAIL  %s\n' "the copy path no longer uses Util.execArgv for the link"
fi
if grep -q 'sequence: "Ctrl+C"' "$PLUGIN_DIR/Panel.qml" \
   && grep -q 'onActivated: root.copyLink()' "$PLUGIN_DIR/Panel.qml"; then
  ok "a window level Ctrl+C shortcut copies the link"
else
  fail=$((fail + 1))
  printf '  FAIL  %s\n' "the copy shortcut is gone or no longer calls copyLink"
fi
# It has to sit inside the key catcher: KeyboardPanel only takes visual children,
# so a Shortcut in the panel body makes the whole panel fail to load.
catcher_line=$(grep -n 'PanelKeyCatcher {' "$PLUGIN_DIR/Panel.qml" | head -1 | cut -d: -f1)
shortcut_line=$(grep -n 'Shortcut {' "$PLUGIN_DIR/Panel.qml" | head -1 | cut -d: -f1)
if [[ -n $catcher_line && -n $shortcut_line && $shortcut_line -gt $catcher_line ]]; then
  ok "the shortcut sits inside the key catcher"
else
  fail=$((fail + 1))
  printf '  FAIL  %s\n' "the shortcut is outside the key catcher, which breaks the panel"
fi
# Super+C needs no handling of its own: Omarchy binds it to Universal copy, which
# injects a CTRL+C into the focused surface. The version field keeps its own Ctrl+C.
if grep -q 'enabled: root.opened && !versionField.activeFocus' "$PLUGIN_DIR/Panel.qml"; then
  ok "the shortcut stands down while the version field is edited"
else
  fail=$((fail + 1))
  printf '  FAIL  %s\n' "the copy shortcut also steals Ctrl+C from the version field"
fi

hostile='https://example.com/x/$(whoami);`uname`;"q"'"'"'e&|>'
got=$(bash -lc 'exec "$@"' bash printf '%s' "$hostile")
if [[ $got == "$hostile" ]]; then
  ok "a hostile link survives the argv route byte for byte"
else
  fail=$((fail + 1))
  printf '  FAIL  %s\n        wanted %s\n        got    %s\n' "a hostile link survives the argv route byte for byte" "$hostile" "$got"
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

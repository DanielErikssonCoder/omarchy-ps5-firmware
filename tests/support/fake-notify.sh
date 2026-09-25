#!/usr/bin/env bash
# A stand-in for omarchy-notification-send, used by tests/run.sh.
#
# The suite has to be able to assert what the plugin WOULD say without a real
# toast appearing on the desktop of whoever runs it. Every call is appended to
# $PS5_NOTIFY_LOG as one line, and the script answers like the real tool: with
# -p it prints the id the daemon assigned, which the caller stores and reuses
# with -r for the next change.
#
# Setting PS5_NOTIFY_FAIL=1 makes it fail like a session with no notification
# daemon: nothing is printed, and the exit code is non-zero.
set -uo pipefail

log=${PS5_NOTIFY_LOG:-/dev/null}
# One line per call, with embedded newlines escaped: the description of a
# firmware change is multi-line, and the suite counts lines to count sends.
printf '%s\n' "${*//$'\n'/\\n}" >>"$log"

if [[ ${PS5_NOTIFY_FAIL:-0} == 1 ]]; then
  echo "fake-notify: no notification daemon (test)" >&2
  exit 1
fi

print_id=0
for arg in "$@"; do
  [[ $arg == -p || $arg == --print-id ]] && print_id=1
done

if ((print_id)); then
  # The real tool returns the daemon's id; the count of calls so far is a
  # stable stand-in, and it changes when a test expects a fresh bubble.
  printf '%s\n' "$((1000 + $(wc -l <"$log")))"
fi

# failure.jq: input is the previous state (or null); output is that state with
# the source failure recorded.
#
# Called with:
#   --arg now              <ISO 8601 timestamp>
#   --arg reason           <short human-readable cause>
#   --argjson threshold    <checks in a row before the source is called down>
#   --argjson notifyAllowed <true|false>
#
# The last good reading is kept exactly as it was. A monitor that blanks its own
# numbers when it cannot reach the source is worse than one that says how old
# the numbers are, so nothing here touches `reading`, `views`, `baseline` or the
# notification key of the last real change: only the failure count moves.
($prev[0] // {reading: null}) as $p
| (($p.failsInARow? // 0) + 1) as $fails
| ($fails >= $threshold) as $down
| (if $notifyAllowed and $down and (($p.notified.key? // "") != ("source-down:" + ($fails | tostring)))
   then {
     key: ("source-down:" + ($fails | tostring)),
     headline: "PS5 firmware source is not answering",
     urgency: "low",
     body: (($fails | tostring) + " checks in a row failed"
            + (if ($p.lastOkAt? // null) != null then "\nLast good reading " + $p.lastOkAt else "" end)
            + "\n" + $reason)
   }
   else null
   end) as $fresh
# A toast that never reached the screen stays pending, so the next run tries
# again instead of losing the news; see the note in merge.jq. Unlike the success
# path this keeps a pending source-down notice too: the source is still down.
| (if $fresh != null then $fresh
   elif (($p.notify? // null) != null and ($p.notified.key? // "") != $p.notify.key)
   then $p.notify
   else null end) as $notify
| $p + {
    schema: 1,
    takenAt: $now,
    sourceOk: false,
    failsInARow: $fails,
    lastError: $reason,
    notify: $notify,
    # An unannounced change stays pending until the toast actually went out;
    # see the note in merge.jq. bin/ps5-firmware owns this key.
    notified: ($p.notified? // {key: "", at: null})
  }

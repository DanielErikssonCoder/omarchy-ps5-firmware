# merge.jq: input is one normalized reading; output is the plugin's state file.
#
# Called with:
#   --slurpfile prev  <state.json or a file containing null when there is none>
#   --arg now         <ISO 8601 timestamp>
#   --arg region      <GLOBAL | us | jp | ...>
#
# The previous state is the only history this plugin has. The upstream API
# keeps none, so everything a person reads as "unchanged for 34 days" is born
# here.
($prev[0] // null) as $p
| (views(.)) as $nv
| (if $p == null or $p.reading == null then {} else ($p.views // {}) end) as $pv
| (if $p == null or $p.reading == null
   then []
   else events($pv; $nv; $region)
   end) as $scoped
# A region going dark is news even when it is not the one on the bar, but it is
# reported once, keyed per region, and never for the watched scope twice.
| (if $p == null or $p.reading == null
   then []
   else [ coverage_events($p.reading; .)[]
          | . as $e
          | select(([$scoped[].key] | index($e.key)) == null) ]
   end) as $extra
| ($scoped + $extra) as $all
| (if $p == null or $p.reading == null
   then null
   else notification($scoped; .; $region)
   end) as $candidate
# The same change is announced once: the key is built from the before and after
# values, so a re-check that changed nothing cannot repeat an old toast. A change
# that was never delivered (no desktop session, the daemon restarting) stays
# pending in `notify` instead of being lost, because the comparison here has
# already moved on to the new values. bin/ps5-firmware clears it by writing the
# key into `notified` once the toast is actually out.
| (if $candidate != null and ($p.notified.key? // "") != $candidate.key
   then $candidate else null end) as $fresh
| (if $fresh != null then $fresh
   elif (($p.notify? // null) != null
         and (($p.notify.key | startswith("source-down:")) | not)
         and ($p.notified.key? // "") != $p.notify.key)
   then $p.notify
   else null end) as $notify
| ($nv[$region] // $nv.GLOBAL) as $watched
| {
    schema: 1,
    takenAt: $now,
    region: $region,
    sourceOk: true,
    failsInARow: 0,
    checks: (($p.checks? // 0) + 1),
    firstSeenAt: ($p.firstSeenAt? // $now),
    lastOkAt: $now,
    reading: .,
    views: $nv,
    view: $watched,
    baseline: {
      latest: (carry(($p.baseline.latest? // {}); $watched.latest; $now)),
      minimum: (carry(($p.baseline.minimum? // {}); $watched.minimum; $now)),
      build: (carry(($p.baseline.build? // {}); $watched.buildHash; $now))
    },
    events: $all,
    history: (((($p.history? // []) + ($all | map(. + {at: $now})))) | if length > 20 then .[-20:] else . end),
    notify: $notify,
    # Which change has actually been ANNOUNCED is decided by the sender, not by
    # this comparison: a toast that never reached the screen (no desktop
    # session, the daemon restarting) has to stay pending so the next run tries
    # again. bin/ps5-firmware marks the key after a successful send.
    notified: ($p.notified? // {key: "", at: null})
  }

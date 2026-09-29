# sony.jq: the assembly half of the Sony source.
#
# The facts the fetch half read out of each regional list come in on stdin, one
# object per region; --slurpfile regions is the table of regions Sony publishes
# for, and --arg checkedAt / --arg sourceUrl say when this run happened and where
# it read. The output is a manifest in exactly the shape lib/core.jq already
# expects, so nothing downstream changes: this file replaces the aggregator that
# used to do the same arithmetic.
#
# Nothing here reads the network, the clock or the filesystem, so every rule
# below can be exercised from a stored answer.

# "14.00.00.00" -> "14.00". Sony publishes the full four-part version; the
# plugin has always shown the first two parts, which is what a person reads off
# the console.
def short:
  if . == null or . == "" then null
  else (tostring | capture("^(?<v>[0-9]+\\.[0-9]+)")? | .v) // null
  end;

def num: if . == null or . == "" then null else (tonumber? // null) end;

([ .[] ] | map({key: .code, value: .}) | from_entries) as $facts
| ($regions[0].regions) as $table

# One row per region Sony has, including the ones that answered nothing: the
# panel shows those as placeholders, exactly as it did before.
| [ $table[]
    | . as $r
    | ($facts[$r.code] // {code: $r.code, ok: false, error: "no answer"}) as $f
    | {
        code: $r.code,
        region: $r.name,
        health: (if ($f.ok // false) then "LIVE" else "UNAVAILABLE" end),
        url: ($f.url // null),
        data: (if ($f.ok // false) then {
            region: ($r.code | ascii_upcase),
            minimum: ($f.minimumRaw | short),
            minimumRaw: ($f.minimumRaw // null),
            minimumSdk: ($f.minimumSdk // null),
            latest: ($f.latestRaw | short),
            latestRaw: ($f.latestRaw // null),
            latestSdk: ($f.latestSdk // null),
            label: ($f.label // null),
            updateType: ($f.updateType // null),
            size: ($f.size | num),
            pupUrl: ($f.pupUrl // null),
            conditions: ($f.conditions | num) // 0
          } else null end),
        error: ($f.error // null)
      }
  ] as $regions
| [ $regions[] | select(.health == "LIVE") ] as $live

# The figure every answering region agrees on. One region lagging behind must
# not move the global reading, and a real disagreement is reported as a
# disagreement (agree below available) rather than quietly resolved. When no pair
# has a majority, the newest one is shown: for someone who watches firmware, "a
# newer version is out" is the fact worth surfacing, and the status says PARTIAL
# so nobody reads it as settled.
| ([ $live[] | {key: "\(.data.latest)|\(.data.minimum)",
                latest: .data.latest, minimum: .data.minimum} ]
   | group_by(.key)
   | map({latest: .[0].latest, minimum: .[0].minimum, agree: length})
   | sort_by(-.agree)
  ) as $groups
| (if ($groups | length) == 0 then null
   else ([ $groups[] | select(.agree == $groups[0].agree) ]
         | max_by([.latest, .minimum]))
   end) as $consensus
| {
    checkedAt: $checkedAt,
    health: (if ($live | length) == 0 then "UNKNOWN"
             elif ($live | length) == ($regions | length) then "LIVE"
             else "PARTIAL" end),
    live: ($live | length),
    cached: 0,
    cacheMinutes: 30,
    source: {name: "Sony", url: $sourceUrl},
    global: {
      latest: ($consensus.latest // null),
      minimum: ($consensus.minimum // null),
      available: ($live | length),
      agree: ($consensus.agree // 0),
      total: ($regions | length)
    },
    regions: $regions
  }

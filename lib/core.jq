# core.jq: the pure half of the data core.
#
# Nothing in this file reads the network, the clock or the filesystem unless it
# is handed in as a parameter, so every rule here can be exercised from a stored
# fixture. shape.jq and merge.jq are thin wrappers that pipe this through.

# The build identity: Sony serves the same version under a new path when the
# image is rebuilt, and the path carries a content hash. The version number
# alone would call a rebuild "no change", which is exactly the case a modder
# cares about.
def build_hash:
  if (. // "") == "" then null
  else (try capture("sys_(?<h>[0-9a-f]+)") catch null) as $m
    | if $m == null then null else $m.h end
  end;

# Raw manifest -> one normalized reading. Every field is optional on the way in:
# a region Sony does not answer for comes back with `data: null`, and the shape
# has to survive that without inventing values.
def shape:
  {
    schema: 1,
    source: {
      name: "psn.etawen.lol",
      url: "https://psn.etawen.lol/api/manifest",
      reportedAt: (.checkedAt // null),
      health: (.health // "UNKNOWN"),
      live: (.live // 0),
      cached: (.cached // 0),
      cacheMinutes: (.cacheMinutes // 30)
    },
    global: {
      latest: (.global.latest // null),
      minimum: (.global.minimum // null),
      available: (.global.available // 0),
      agree: (.global.agree // 0),
      total: (.global.total // 0)
    },
    regions: [
      (.regions // [])[] | {
        code: (.code // null),
        name: (.region // null),
        status: (.health // "UNKNOWN"),
        latest: (.data.latest // null),
        minimum: (.data.minimum // null),
        build: (.data.label // null),
        buildHash: ((.data.pupUrl // "") | build_hash),
        size: (.data.size // null),
        pupUrl: (.data.pupUrl // null),
        conditions: ((.data.conditions // []) | length),
        error: (.error // null)
      }
    ]
  };

# The consensus build: the one every live region agrees on. Disagreement is
# reported as disagreement rather than silently resolved to the first answer.
def consensus($reading):
  [ $reading.regions[] | select(.status == "LIVE") | .buildHash ] | unique as $hashes
  | if ($hashes | length) == 1 then $hashes[0] else null end;

def consensus_build($reading):
  [ $reading.regions[] | select(.status == "LIVE") | .build ] | unique as $labels
  | if ($labels | length) == 1 then $labels[0] else null end;

def consensus_size($reading):
  [ $reading.regions[] | select(.status == "LIVE") | .size ] | unique as $sizes
  | if ($sizes | length) == 1 then $sizes[0] else null end;

# One view per scope, so the bar and the panel never derive anything themselves:
# they look up `views[their region]` and print it. Building all of them here
# also means changing the region setting needs no re-check.
def views($reading):
  ({ GLOBAL: {
       code: "GLOBAL",
       label: "Every region that answers",
       latest: $reading.global.latest,
       minimum: $reading.global.minimum,
       build: consensus_build($reading),
       buildHash: consensus($reading),
       size: consensus_size($reading),
       status: (if $reading.global.available > 0
                  and $reading.global.agree == $reading.global.available
                then "LIVE" else "PARTIAL" end),
       readable: $reading.global.available,
       total: $reading.global.total,
       pupUrl: (first($reading.regions[] | select(.status == "LIVE") | .pupUrl) // null)
     } })
  | reduce ($reading.regions[]) as $r (.;
      .[$r.code] = {
        code: $r.code,
        label: $r.name,
        latest: $r.latest,
        minimum: $r.minimum,
        build: $r.build,
        buildHash: $r.buildHash,
        size: $r.size,
        status: $r.status,
        readable: (if $r.status == "LIVE" then 1 else 0 end),
        total: 1,
        pupUrl: $r.pupUrl,
        error: $r.error
      });

# The changes worth telling a person about, scoped to the region they watch.
# Silence is the default: an unchanged reading produces an empty list, which is
# the whole reason this plugin exists rather than a bookmark to the website.
def events($prevViews; $nextViews; $scope):
  ($prevViews[$scope] // null) as $was
  | ($nextViews[$scope] // null) as $is
  | if $was == null or $is == null then []
    else
      [
        (if ($was.latest != null and $is.latest != null and $was.latest != $is.latest)
         then {scope: $scope, kind: "latest", from: $was.latest, to: $is.latest,
               key: ($scope + ".latest:" + $was.latest + "->" + $is.latest)} else empty end),
        (if ($was.minimum != null and $is.minimum != null and $was.minimum != $is.minimum)
         then {scope: $scope, kind: "minimum", from: $was.minimum, to: $is.minimum,
               key: ($scope + ".minimum:" + $was.minimum + "->" + $is.minimum)} else empty end),
        (if ($was.buildHash != null and $is.buildHash != null
             and $was.buildHash != $is.buildHash and $was.latest == $is.latest)
         then {scope: $scope, kind: "build", from: ($was.build // $was.buildHash),
               to: ($is.build // $is.buildHash),
               key: ($scope + ".build:" + ($was.buildHash[0:12]) + "->" + ($is.buildHash[0:12]))}
         else empty end),
        (if $was.status != $is.status
         then {scope: $scope, kind: "coverage", from: $was.status, to: $is.status,
               key: ($scope + ".coverage:" + $was.status + "->" + $is.status)} else empty end)
      ]
    end;

# Coverage is worth knowing about in every region, not only the one on the bar:
# a region going dark is how "the number looks stale" starts.
def coverage_events($prevReading; $nextReading):
  [ $nextReading.regions[] as $r
    | ($prevReading.regions[]? | select(.code == $r.code)) as $was
    | select($was.status != $r.status)
    | {scope: $r.code, kind: "coverage", from: $was.status, to: $r.status,
       key: ($r.code + ".coverage:" + $was.status + "->" + $r.status)}
  ];

# One notification, or none. Plain text only: it is read in a toast, not parsed.
def notification($events; $reading; $scope):
  if ($events | length) == 0 then null
  else
    ($events | map(select(.scope == $scope)) | if length == 0 then $events else . end) as $shown
    | {
        key: ([$shown[].key] | sort | join("|")),
        headline: (
          if any($shown[]; .kind == "latest") then
            "PS5 firmware " + ([$shown[] | select(.kind == "latest") | .to] | first)
          elif any($shown[]; .kind == "minimum") then
            "PS5 minimum raised to " + ([$shown[] | select(.kind == "minimum") | .to] | first)
          elif any($shown[]; .kind == "build") then
            "PS5 firmware image rebuilt"
          else "PS5 region " + ([$shown[] | select(.kind == "coverage") | .scope] | first)
               + " is no longer readable"
          end
        ),
        body: ([ $shown[]
                 | if .kind == "latest" then "Latest " + .from + " → " + .to
                   elif .kind == "minimum" then "Minimum " + .from + " → " + .to
                   elif .kind == "build" then "Rebuilt image, version unchanged"
                   else "Region " + .scope + ": " + .from + " → " + .to
                   end ] | join("\n")),
        # A real firmware change is worth a normal toast; a region that stops
        # answering is background noise and stays low.
        urgency: (if any($shown[]; .kind == "latest" or .kind == "minimum" or .kind == "build")
                  then "normal" else "low" end)
      }
  end;

# How long a value has been what it is. The upstream API keeps no history at
# all, so this is the part of the plugin that cannot be borrowed from anyone.
def carry($prevBaseline; $value; $now):
  if $value == null then null
  elif ($prevBaseline.value? // null) == $value and ($prevBaseline.since? // null) != null
  then {value: $value, since: $prevBaseline.since}
  else {value: $value, since: $now}
  end;

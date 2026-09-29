# Fixtures

`manifest-2026-09-25.json` is a real reply from `https://psn.etawen.lol/api/manifest`,
stored whole on 2026-09-25 so the tests describe the actual shape of the data
rather than what the API was believed to return.

That aggregator was shut down on 2026-09-29 and the plugin now reads Sony's own
regional lists (`sony/`, below). The file is kept as it is: it is the shape the
data core in `lib/core.jq` reads, and it is the source of the comparisons in the
tests that do not involve the network. `lib/sony.jq` produces that same shape out
of Sony's lists, which is why every case here still means what it says.

`sony/` holds the other half: `updatelist-us-14.00.xml` is a real regional list
from Sony, stored on 2026-09-29, and the rest are edits of it that change exactly
one thing, next to a file that is not a list at all.

The other four JSON files are derived from the base by changing exactly one thing
each, which is what makes a failing test point at a single rule:

| File | The one change | The rule it exercises |
|---|---|---|
| `manifest-latest-15.00.json` | every answering region, and the aggregate, move to 15.00 with a new label | a new latest version |
| `manifest-minimum-14.00.json` | minimum raised to 14.00, latest deliberately left at 14.00 | a raised force-update baseline |
| `manifest-rebuilt.json` | the image hash in the download path changes, version and minimum untouched | the same version rebuilt |
| `manifest-region-down.json` | `us` becomes unreadable and the aggregate counts drop | a region losing coverage |

Regenerate a derived fixture with the same edit it names, or replace the base
file the next time the API's shape changes, then run `../run.sh`.

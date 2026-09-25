# Fixtures

`manifest-2026-09-25.json` is a real reply from `https://psn.etawen.lol/api/manifest`,
stored whole on 2026-09-25 so the tests describe the actual shape of the data
rather than what the API was believed to return.

The other four are derived from it by changing exactly one thing each, which is
what makes a failing test point at a single rule:

| File | The one change | The rule it exercises |
|---|---|---|
| `manifest-latest-15.00.json` | every answering region, and the aggregate, move to 15.00 with a new label | a new latest version |
| `manifest-minimum-14.00.json` | minimum raised to 14.00, latest deliberately left at 14.00 | a raised force-update baseline |
| `manifest-rebuilt.json` | the image hash in the download path changes, version and minimum untouched | the same version rebuilt |
| `manifest-region-down.json` | `us` becomes unreadable and the aggregate counts drop | a region losing coverage |

Regenerate a derived fixture with the same edit it names, or replace the base
file the next time the API's shape changes, then run `../run.sh`.

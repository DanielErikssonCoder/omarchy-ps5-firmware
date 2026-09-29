# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-09-29

### Changed

- The readings now come from Sony's own update hosts instead of the community aggregator
  `psn.etawen.lol`, whose author shut it down on 2026-09-29. Nothing else changed: the manifest the rest of
  the plugin reads keeps its shape, so the comparison, the state file, the notifications and the panel are
  the same code they were.
- Each of the thirteen regional lists is read over https, measured against Sony's own root certificate,
  which now travels with the plugin (`assets/scei-dnas-root-05.pem`). Sony's certificate is issued by Sony's
  own authority rather than a public one, so that root is the anchor: the read is encrypted, the server has
  to prove it is Sony's, and nothing on the way can change a byte of it. A test fails if the file changes,
  so replacing the anchor is a deliberate, visible act.
- GLOBAL is computed here now: the pair of versions the answering regions agree on. One region lagging
  behind does not move it, and a real disagreement is shown as one, with the newest figure and a `PARTIAL`
  row. Eight of the thirteen regions answer (us, jp, uk, au, sa, ru, cn, br); eu, kr, mx, tw and hk do not,
  exactly as before.
- The check no longer relies on somebody else's cache: the regional lists carry no cache header, so the
  interval setting is the only thing that decides how often they are read.

### Added

- `lib/sony.sh`, the fetch half: one request per region, with the same timeout, size cap and no-redirect
  rule as any other source, and our own wording for every way a region can fail.
- `lib/sony.jq`, the arithmetic, which runs with no network at all, and `lib/regions.json`, the region
  table with the names the panel has always shown.
- `xmllint` (from `libxml2`) as a declared dependency: `jq` cannot read XML, and libxml2 is installed on any
  Omarchy system.

### Fixed

- The state file and the id of the notification that is updated in place are read as
  plain, bounded files. A path that is not a regular file (a FIFO, or a link) or that is
  larger than 1 MiB is treated as "no previous reading" instead of being followed, so a
  substituted path cannot hold a scheduled check up or hand the comparison an unbounded
  file. Both are also written through a fresh file in the same directory and renamed over
  the target, so a name that was replaced by a link is replaced rather than written
  through. Raised by the marketplace review.

### Notes

- The test suite grew from 74 to 112 cases, including a stand-in for Sony's hosts. It covers a region that
  lags behind another, a list belonging to a different region, a reply that is not a list, no region
  answering at all, the wording of a failed region, the pinned certificate, that each region is asked
  exactly once per check, and the state file being a link, a FIFO or larger than the cap.

## [0.2.1] - 2026-09-28

### Fixed

- A source that answers with a redirect is refused instead of followed. A redirect target is chosen by
  whoever answers, and it can be a plain HTTP address on this machine or on the local network, which is
  never a source this plugin should talk to. Following none of them means exactly one host is contacted
  per check, and the reason is recorded in the state file. Raised by the marketplace review.

### Changed

- The test suite grew from 68 to 74 cases: six for the redirect rule. Three of those assert on which
  addresses a stand-in source was actually asked for, so the check is on what the plugin did rather than
  on which flags it passed to `curl`.

## [0.2.0] - 2026-09-27

### Added

- A Copy button beside the download link, and Ctrl+C or Super+C while the panel is open. A selection made by
  hand wins over the whole link. The link goes to `wl-copy` as an argument through the shell's own argv runner,
  so a link that contains shell metacharacters is copied as data and never interpreted.
- The test suite grew from 54 to 68 cases and still runs in about a second: six for the reply size cap (a local
  file past the limit, a reply that announces 512 MiB, a reply that announces nothing and streams 16 MiB, and the
  recovery afterwards), three for the plain-text labels, and five for the copy path.

### Fixed

- A reply from the source is capped at 1 MiB. A reply that announces more than that, sends more than that, or
  never stops sending is refused, and the reason is recorded in the state file. Raised by the marketplace
  review: the source announces no size, so a timeout alone left the disk unprotected.
- The panel reads every string that comes from the manifest as plain text (`textFormat: Text.PlainText`). Qt's
  default is `AutoText`, which interprets a string as HTML, so a version or build label carrying an image tag
  could have made the panel fetch a URL of the manifest's choosing. Also raised by the marketplace review.

## [0.1.0] - 2026-09-25

### Added

- A bar widget with the PlayStation mark from Simple Icons, tinted to the theme and following the state:
  normal ink while the reading is quiet, the theme's urgent colour when something changed in the last day, and
  dimmed when the source stops answering. The tooltip carries the newest reading and what each click does.
- Left click opens a panel with the latest and minimum versions, the build hash and the image size, how many
  regions answered, the region matrix, the download link for the newest image, and a field where your own
  firmware version is compared against the minimum and the latest.
- One notification, updated in place, for four changes: a new latest version, a raised minimum, a region that
  stops being readable, and the same version rebuilt. A fifth, at low urgency, when the source has failed four
  checks in a row.
- `bin/ps5-firmware`, the headless half: `--once`, `--print`, `--json`, `--region`, `--source`, `--state`,
  `--if-stale`, `--now`, `--no-notify`, `--no-source-down-notify` and `--quiet`, writing one state file that
  the widget, the panel and the command line all read.
- Five settings: check interval, region on the bar, your firmware version, notify on change, and notify when
  the source stops answering.
- A test suite of 54 cases that runs offline against a recorded API reply and four variants that change one
  thing each, with a stand-in for the notification tool so the suite never touches the desktop it runs on.

[0.3.0]: https://github.com/DanielErikssonCoder/omarchy-ps5-firmware/releases/tag/v0.3.0
[0.2.1]: https://github.com/DanielErikssonCoder/omarchy-ps5-firmware/releases/tag/v0.2.1
[0.2.0]: https://github.com/DanielErikssonCoder/omarchy-ps5-firmware/releases/tag/v0.2.0
[0.1.0]: https://github.com/DanielErikssonCoder/omarchy-ps5-firmware/releases/tag/v0.1.0

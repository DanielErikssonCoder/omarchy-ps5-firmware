# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.2.0]: https://github.com/DanielErikssonCoder/omarchy-ps5-firmware/releases/tag/v0.2.0
[0.1.0]: https://github.com/DanielErikssonCoder/omarchy-ps5-firmware/releases/tag/v0.1.0

# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-09-25

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

[1.0.0]: https://github.com/DanielErikssonCoder/omarchy-ps5-firmware/releases/tag/v1.0.0

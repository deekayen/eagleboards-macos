# CLAUDE.md -- working notes for this repo

Guidance for anyone (human or AI) making changes here. Read
[CONTRIBUTING.md](CONTRIBUTING.md) first; it holds the architecture and the
rules. This file adds what an agent in particular needs.

## What this is

The native Mac version of the Java Eagle Board Scheduler
(`deekayen/eagleboards`), an Eagle Scout board of review check-in and room
scheduler. Swift 6, SwiftUI, macOS 14+, Apple silicon only -- there is no
Intel build, by the owner's decision. The sign-in stations still register by
web page, served by an embedded Hummingbird server; every operator screen is
a native window. See `PROVENANCE.md`.

## Build and verify

- Xcode is installed but may not be the selected developer directory. Use it
  without changing system settings:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
- `swift test` runs everything headless: the rules, a whole board evening,
  the data-file dialect, and the check-in server (in memory, plus one test on
  a real socket).
- `scripts/build-app.sh` builds `build/Eagle Boards.app`.
- To look at the app, run it with `EAGLEBOARDS_DATA_FOLDER` pointing at a
  scratch folder of **synthetic** people and `EAGLEBOARDS_PORT` on a spare
  port. Never load a real `Master_AdultHistory.csv` into anything you
  screenshot. `EAGLEBOARDS_DATA_FOLDER` also switches SignUpGenius off (no
  keychain read, no import on open), so the real key cannot pull minors'
  sign-ups into synthetic data. Never set `EAGLEBOARDS_SIGNUPGENIUS=1` for a
  screenshot run.
- Prefer pushing over re-running the suite locally; CI is the gate.

## Standing rules

- **Push to `main`. Never open pull requests** on this repository: GitHub keeps
  `refs/pull/*` forever, beyond the reach of a history rewrite.
- **No AI attribution** in commits, PR text, or anywhere in history.
- **Commits are GPG-signed** (`commit.gpgsign` is on); expect a pinentry prompt.
- **Never commit participant data or secrets.** Install the hook:
  `git config core.hooksPath scripts/hooks`.
- **The data files are the contract** with the Java app. Change their shape
  only with a test in `FileFormatTests` and a reason that survives the Java
  app reading the result.
- **Add a test with every fix**, and a `BoardEveningTests` case when a change
  touches seating, running or tearing down a board. Scenarios added to the Java
  project's `test-board-evening.sh` are mirrored there too (and in the Windows
  version); where one cannot arise here, the stand-in test says why.
- **Board suggestions** (`BoardSuggestion`) weigh the whole waiting line;
  the same algorithm and test cases are in the Java (`proposeBoard`) and
  Windows (`SchedulerLogic.AutoSelect`) versions. Change all three together.
  Just above that, volunteers who came for any board (`Adult.cameForAnyBoard`:
  not linked to a youth, or Wood Badge) go before a youth's own leaders.
  The last tie-break is who has waited longest to volunteer since last free
  (`BoardSuggestion.freeSinceTimes`), after saving chairs and flexible adults.
- **Adult sign-in answers.** "No thanks" to a board type is stored as the
  role `Unavailable` (Seat Board refuses it). `WoodBadge` and `Supporting`
  (youth IDs, `|`-separated) are appended to the adult record, per night,
  never copied into the history; `/api/scout-choices` feeds the form's list.
  Start Review and Locate name supporting adults first. The adult panel's Link
  button (`EventNight.setSupporting`) links or unlinks them after sign-in.
- **No `var##` names**, even to match anything. CI fails on them.
- **District-neutral branding**, settled: never add a district or council name.

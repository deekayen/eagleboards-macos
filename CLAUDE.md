# CLAUDE.md -- working notes for this repo

Guidance for anyone (human or AI) making changes here. Read
[CONTRIBUTING.md](CONTRIBUTING.md) first; it holds the architecture and the
rules. This file adds what an agent in particular needs.

**Read `SPEC.md` in `deekayen/eagleboards-shared` before changing the
operator screen, the check-in pages, the board rules or the data files.**
It is the source of truth for anything more than one version of Eagle
Boards does; this repo does not decide shared behavior on its own.

## What this is

The native Mac version of the Java Eagle Board Scheduler
(`deekayen/eagleboards-java`), an Eagle Scout board of review check-in and room
scheduler. Swift 6, SwiftUI, macOS 14+, Apple silicon only -- there is no
Intel build, by the owner's decision. The sign-in stations still register by
web page, served by an embedded Hummingbird server; every operator screen is
a native window. See `PROVENANCE.md`.

## Build and verify

- Xcode is installed but may not be the selected developer directory. Use it
  without changing system settings:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
- `swift test` runs everything headless: the rules, a whole board event,
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
- **Add a test with every fix**, and a `BoardEventTests` case when a change
  touches seating, running or tearing down a board. Scenarios added to the Java
  project's `test-board-event.sh` are mirrored there too (and in the Windows
  version); where one cannot arise here, the stand-in test says why.
- **The check-in pages are shared** (SPEC.md D-18): the five files in
  `Sources/CheckInServer/Resources/CheckIn/` are copies of
  `eagleboards-shared/checkin`, pinned by `checkin-pages.lock`. **Never edit
  them here**; CI fails if they differ from the pinned commit. Change them in
  the shared repo (WCAG 2.2 AA: its `check-contrast.js` and an axe scan),
  then copy all five and update the lock.
- **No birthdate** (SPEC.md D-7, O-5): nothing asks for, keeps, pre-fills,
  shows or exports one; `DOB` stays a column in the data files, empty for
  new youth, and one already on file is left alone.
- **No youth phone number** (SPEC.md D-8): the same for a youth's `Phone`,
  which `Scout.signInColumns` and the SignUpGenius import no longer copy.
  Anything saved outside the data folder goes through `Scout.forExport`,
  which blanks `Scout.withheldColumns`. Adults keep their numbers everywhere.
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
  Start Review and the inspector's With Them list name supporting adults
  first. Link an Adult there, and the Adult menu, link or unlink them after
  sign-in (`EventNight.setSupporting`).
- **The scheduler follows the Mac layout**: sidebar, list, inspector. Every
  action lives in the Board, Adult or Room menu (and the matching context
  menu), not in buttons along a panel. Report outcomes as alerts titled with
  what failed, or show them in the inspector; no self-dismissing toasts.
  A change the operator makes registers its inverse with Undo (`AppModel`'s
  `change` and `changeBoard`) instead of asking "Are you sure?"; a board step
  is undone with `EventNight.restoreBoard`.
- **No `var##` names**, even to match anything. CI fails on them.
- **District-neutral branding**, settled: never add a district or council name.

# CLAUDE.md: working notes for this repo

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
scheduler. Swift 6, SwiftUI, macOS 14+, Apple silicon only; there is no
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
  screenshot run. `EAGLEBOARDS_APPEARANCE=dark|light` picks the appearance
  for the run; never change the system's.
- Prefer pushing over re-running the suite locally; CI is the gate.
- CI builds with the Xcode on GitHub's `macos-latest` image, which can be
  older than the one here (Xcode 26.6 as of 2026-10-25). Code that builds
  locally can fail there: its `CommandsBuilder` takes at most ten items in a
  block, so `EagleBoardsCommands` groups its menus with `Group`. Check an API
  newer than macOS 14 against that SDK before relying on it.

## Standing rules

- **Push to `main`. Never open pull requests** on this repository: GitHub keeps
  `refs/pull/*` forever, beyond the reach of a history rewrite. The repository
  is public, so everything committed, history included, is world-readable.
- **No AI attribution** in commits, PR text, or anywhere in history.
- **Commits are GPG-signed** (`commit.gpgsign` is on); expect a pinentry prompt.
- **Never commit participant data or secrets.** Install the hook:
  `git config core.hooksPath scripts/hooks`. CI's "No participant data in the
  tree" step catches a file that got in anyway; keep its pattern in step with
  `scripts/hooks/pre-commit` and `.gitignore`.
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
  the same algorithm is in the Java (`proposeBoard`) and Windows
  (`SchedulerLogic.AutoSelect`) versions. Change all three together.
  **Fill the Rest** (`BoardSuggestion.fill`, SPEC.md D-12) keeps the
  operator's picks and adds a chair and members around them, as Java's
  `fillBoard` and Windows' `SchedulerLogic.FillBoard` do.
- **The rule and auto-select cases are shared** (SPEC.md D-5): the files in
  `Tests/EagleBoardsCoreTests/Resources/cases/` are copies of
  `eagleboards-shared/cases`, pinned by `test-cases.lock`, and
  `SharedCaseTests` runs every one through `BoardRules` and
  `BoardSuggestion`. **Never add or edit a case here**; CI fails if the
  copies differ from the pinned commit. Add it in the shared repo, copy the
  `*.json` here and update the lock. `BoardRulesTests` keeps only what the
  Mac alone has (seating review, the suggestion's room, locate, timers).
  Just above that, volunteers who came for any board (`Adult.cameForAnyBoard`:
  not linked to a youth, or Wood Badge) go before a youth's own leaders.
  The last tie-break is who has waited longest to volunteer since last free
  (`BoardSuggestion.freeSinceTimes`), after saving chairs and flexible adults.
- **Adult sign-in answers.** "No thanks" to a board type is stored as the
  role `Unavailable` (Seat Board refuses it). `WoodBadge` and `Supporting`
  (youth IDs, `|`-separated) are appended to the adult record, per event,
  never copied into the history; `/api/scout-choices` feeds the form's list, which leaves out
  a youth here for a project proposal, since only a board of review has an introduction (D-23).
  Start Review and the inspector's With Them list name supporting adults
  first. Link an Adult there links them after sign-in, and a row's context
  menu or Board › Unlink Introducer unlinks them (`BoardEvent.setSupporting`).
- **The scheduler follows the Mac layout**: the Event page's youth list and
  room cards with an inspector for the selected youth's board, and a table per
  other page with no inspector, and no sidebar (SPEC.md P-1, P-6, as in the
  Java and Windows versions). The View
  menu chooses Event or a page per table (Results, Adults, Youth,
  Pre-Registered, Rooms, and the read-only Adult History CSV), edited in
  place with
  `EditableText` and `EditableChoice` through `AppModel.editYouth`,
  `editAdult` and `editRoomType`. The View menu's eight pages, Approved
  Proposals last, take Command-1 to Command-8 where Windows has Ctrl+1 to 8
  (P-3), and the Window menu's items have no keys. A changed cell stays off
  the Undo stack,
  and who sits on a board or which room anyone is in is never typed into a
  table (P-6), nor a youth's status, which the pages show read-only;
  `BoardEvent.updateYouth` also refuses Seated, In review, or changing a
  sitting board's status, whoever calls it. An
  adult's `signInColumns` edited on Adults reach the adult history
  (`updateAdult` copies them across); nothing edits the history directly. There is no records window. Help › Donate… is the Donate
  link (D-17). Every action lives in the Board, Adult or Room menu (and the
  matching context menu), not in buttons along a panel. Report outcomes as
  alerts titled with what failed, or show them in the inspector; no
  self-dismissing toasts.
  A change the operator makes registers its inverse with Undo (`AppModel`'s
  `change` and `changeBoard`) instead of asking "Are you sure?", except Remove
  Room…, which asks first, naming the room, though Undo also takes it back
  (SPEC.md O-2, amended 2026-10-24); a board step
  is undone with `BoardEvent.restoreBoard`.
- **A command acts only on what the page shown has in view** (CONTRIBUTING.md
  rule 13). The inspector, the toolbar's next-step button and the Board
  menu's steps are the Event page's alone; the Room menu is the Event and
  Rooms pages'; Adult › Mark Gone Home and Mark Back are the Adults page's.
  `SchedulerPage` answers it (`showsBoard`, `showsRooms`, `listsAdults`,
  `listsAdultHistory`, `listsYouth(with:)`), with `SchedulerPageTests`. A
  selection is kept across pages and never acted on from one that cannot show
  it: board commands go through `AppModel.boardYouth`, rooms through
  `selectedRoom`, adults through `selectedAdults`, so a key, a double-click or
  a drop that reaches the model from another page does nothing. Menus keep
  every item, dimmed (`MenuCommand`; a submenu is a `SubmenuCommand`, since SwiftUI
  leaves a disabled `Menu` or `Picker` lit in the menu bar). `AppModel.showsInspector` is the
  operator's choice and no page change writes it
  (`SchedulerPage.inspectorChoice`). Show on Event Page takes a youth
  (Results, Youth) or a room (Rooms) to where the board is. No page has both
  a table of adults to pick from and a board in view, so the Adult menu does
  not put an adult on a board, make them chair, or link them as an introducer;
  the inspector does, and the Board menu has Chair and Unlink Introducer. The
  Adult menu holds Add Adult…, Sign In for Today, Mark Gone Home, and Mark
  Back. Undo and Redo work from every page, so they bring the change into view.
  Every `registerUndo` and `change` call passes a reveal (it has no default),
  and `changeBoard` reveals the youth's board. A reveal is
  `AppModel.revealBoard(of:)`, `revealRooms(selecting:)`, or
  `revealAdults(_:)`; each asks `SchedulerPage.revealing(_:)` for the page and
  calls `show`. A board change, linking an introducer included, is the Event
  page's; a room change stays on Event or Rooms and otherwise goes to Event;
  Mark Gone Home and Mark Back go to Adults. `SchedulerPageTests` pins where
  each lands from all eight pages.
- **Accessibility follows Apple's HIG** (CONTRIBUTING.md rule 12). An icon
  beside words is a `Label`; an icon-only control has an
  `.accessibilityLabel` naming what it does and a `.help` tag. A value drawn
  as a mark (Wood Badge, a status badge, an `EditableChoice`) has its words in
  `accessibilityLabel` or `accessibilityValue`, and a " · " line is read
  through `spokenList`. Titles take `.heading(_:)`. What VoiceOver hears of a
  step, an arrival, or a count is built in `EagleBoardsCore`, with a test;
  `Speech.say` says it with nothing on screen (D-14). Context menus show only
  what applies, with no keys (`MenuCommand`). Tab reaches every control, room
  cards included, and a new shortcut takes no key macOS uses. Help and
  messages say click for a button and choose for a menu item. They write paths
  as File › Export List… and keys as Command-Return, and name places (the
  toolbar, Free for a Final Board) instead of directions or bare symbols. When
  mirroring Windows, leave out its access keys, F6 between panes, and its
  select-for-click wording.
- **No `var##` names**, even to match anything. CI fails on them.
- **District-neutral branding**, settled: never add a district or council name.

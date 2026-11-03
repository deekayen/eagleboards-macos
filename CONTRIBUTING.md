# Contributing

## Shape of the thing

A Swift package with three targets, layered so the rules can be tested
without a window or a socket:

```
  Sign-in tablet (browser)                     The Mac
        |  /  /youth_register  /adult_register       |
        |  /api/checked-in  /api/scout-choices       |  SwiftUI windows:
        |  /api/*-lookup  /register-youth            |  Scheduler, Sign-In
        |  /register-adult                           |  Code, Settings, Help
        +----------------------+                     |
                               |                     |
                     +---------v---------+   +-------v--------+
                     |  CheckInServer    |   |  EagleBoards   |
                     |  (Hummingbird)    |   |  (the app)     |
                     +---------+---------+   +-------+--------+
                               |   main actor        |
                               +---------+-----------+
                                         |
                              +----------v-----------+
                              |  EagleBoardsCore     |  records, CSV files,
                              |  BoardEvent          |  board rules, every
                              +----------+-----------+  lifecycle step
                                         |
                                  data folder on disk
```

| Target | What lives there |
| --- | --- |
| `EagleBoardsCore` | `Records.swift` (the record types), `DataFiles.swift` (the CSV and `config.properties` dialects), `BoardRules.swift` (composition rules, board suggestion, locating leaders, room timers), `BoardEvent.swift` (one event's state and every change to it), `BoardDrafts.swift` (the boards drawn up for waiting youth before Seat Board, and when a proposal is made again), `SignUpGenius.swift`, `LaunchSettings.swift` (saved preferences and the development environment variables), `SignInNetwork.swift` (the networks the Mac is on, and the one the sign-in station serves). No UI, no server. |
| `CheckInServer` | The web server for the tablets, and the sign-in pages in `Resources/CheckIn`. It serves those pages and the six calls they make, and nothing else. |
| `EagleBoards` | The SwiftUI app. `AppModel` holds which event is open, runs the server, and keeps the operator's work in progress. |

`BoardEvent` is `@MainActor` and `@Observable`. The windows read it directly;
the server hops onto the main actor to register someone. So a sign-in shows
up on the scheduler the moment it lands, with no polling, and there is only
one thread that ever changes the data.

## Build, run, verify

Needs a Mac with Apple silicon, macOS 15 or later, and Xcode (or its command
line tools) with Swift 6. As of 2026-11-03 CI runs the tests and launches the
built app on macOS 15 and 26; the maintainer runs Eagle Boards on macOS 27. macOS 14
is unsupported: GitHub retired its runner on 2026-11-02, and nothing here can
test it.

```bash
swift build
```

```bash
swift test
```

```bash
scripts/build-app.sh
```

The last one produces `build/Eagle Boards.app`, signed ad hoc. It is built
for Apple silicon only; Intel Macs are not supported.

The icon is `Artwork/AppIcon.icns`, committed so the build needs no drawing
tools. After changing `Artwork/EagleBoards.svg` (the same drawing as the
Windows version's icon), rebuild it with `scripts/make-icon.sh`, which needs
`brew install librsvg`.

To run against synthetic data without touching the folder the app remembers:

```bash
EAGLEBOARDS_DATA_FOLDER=/tmp/eb-scratch EAGLEBOARDS_PORT=18123 "build/Eagle Boards.app/Contents/MacOS/Eagle Boards"
```

With `EAGLEBOARDS_DATA_FOLDER` set, SignUpGenius is off for the run: the app
does not read the key from your keychain, so opening today's event cannot
import the district's real sign-ups into the scratch folder or put an "Imported"
notice in a screenshot. Set `EAGLEBOARDS_SIGNUPGENIUS=1` as well only when you mean to
test the import itself, and never screenshot the result. Preferences given on
the command line (`-importSignUpsOnOpen NO`, `-checkInPort 18123`) work too.
`EAGLEBOARDS_NETWORK=en0` (or `all`) picks the network the sign-in station
serves for that run, over the one chosen in Settings › General; 127.0.0.1
answers whichever it is.

`EAGLEBOARDS_APPEARANCE=dark` (or `light`) sets the app's appearance for that
run alone, whatever the system's, so a screenshot in each needs no change to
System Settings. The README's pictures in `docs/images/` are shot this way from
the demo event in `deekayen/eagleboards-shared` (its `WEBSITE.md` says how),
with the window at 1280 by 738 and `-youthListWidth 320`.

Swift code is formatted with Apple's `swift-format`, which ships with Xcode and
reads `.swift-format` (4-space indent, 120 columns). CI lints with `--strict`.
Format your changes before committing:

```bash
xcrun swift-format format -i --recursive Sources Tests
```

**Prefer pushing over re-running everything locally.** CI (`build.yml`) runs
the tests, builds the app, checks the bundle, and runs the guards
below. Run things locally to debug what CI found, or to iterate.

## The rules this code keeps

1. **CI is the acceptance gate.** Keep it green. Add a test when you fix a
   bug, and a case in `BoardEventTests` when you change how a board is
   seated, run, or torn down. A rule with no test is a rule that comes back.
2. **Never commit participant data or secrets.** Data folders live outside
   the repository. `.gitignore` and `scripts/hooks/pre-commit` block CSVs,
   dated folders, `Master_AdultHistory*`, `config.properties`, and
   `LOGIN_INFO*`. Install the hook once per clone:
   `git config core.hooksPath scripts/hooks`.
   [SECURITY.md](SECURITY.md) lists what is sensitive, the checks behind the
   hook, and how to report a vulnerability.
3. **Test against synthetic data, never real data.** Tests create throwaway
   folders of made-up people. Never point the app at the real adult history
   while taking screenshots, or let it use the SignUpGenius key (see above).
4. **The data files are the contract.** Both this app and the Java Eagle Board
   Scheduler read and write them, so a district can move between the two, or
   fall back to the Java app at the event. Keep column names, column order,
   ID shapes, and the comma dialect exactly as `FileFormatTests` pins them.
5. **The network gets the sign-in pages and nothing more.** Every operator
   screen is a window. Anything the server returns is trimmed to what its page
   shows; no call takes a column name. `CheckInServerTests` asserts the old
   operator paths are 404. Keep it that way.
6. **Board composition rules live in two places, on purpose.** `SeatingReview`
   explains them to the operator, and asks for confirmation where a rule
   allows it. `BoardEvent.seatBoard` refuses the hard ones again, whatever
   called it. Both must agree:
   - **Size.** A board of review has three to six members (GTA 8.0.0.3): fewer
     refused, four to six confirmed, seven refused. A project proposal review
     is not a board of review (GTA 9.0.2.4); the district runs it with two,
     under the same ceiling.
   - **Chair is binding.** The chair's role for that board type must be
     `Chair`, and the chair must be on the board. When the qualified chairs are
     all busy, the answer is to promote someone on the Adults page, never to
     hand the gavel to a Member.
   - **One board at a time.** An adult with a `Room` is committed to it. `N/A`
     is what Adult › Mark Gone Home leaves for someone gone home.
   - **Same unit.** A same-unit member is an overridable warning (this
     council forbids them; the national rule does not). A board made *entirely*
     of the youth's unit is refused (GTA 8.0.3.0 #2). Deliberately not checked
     in `seatBoard`: it is a judgment call.
7. **Lifecycle:** Registered -> Seated -> InProgress -> Completed, or
   Registered -> Postponed. Seating and starting are separate so the two phases
   can be timed apart: seating convenes the board with the paperwork while the
   youth waits (GTA 8.0.3.0 #8), and Start Review brings them in. Only an
   InProgress board can be completed. Seated and InProgress are reached only
   through those steps, which give the youth a room and members: the pages
   show the status read-only, and `BoardEvent.updateYouth` refuses to set a
   sitting status or to change a board that holds a room (Reset Board and
   Complete free it). `Verified`
   survives on legacy records only; nothing sets it.
8. **Names say what things are for.** No `var1`-style names anywhere. CI
   greps for `var` followed by digits and fails.
9. **Branding is district-neutral.** The app never displays whose district
   it is.
10. **Help's Keyboard shortcuts sections are the key contract.** They list
    every key the app answers (`HelpView.guide`). Change them in the same
    commit as the key.
11. **Focus is never left on a control that went away.** After a step taken
    from an inspector button, it moves to the next step's button or to the
    youth's row in the Event page's list (`StepFocus`); a list row that leaves
    hands it to the row now in its place (`ListFocus`).
12. **Accessibility follows Apple's Human Interface Guidelines.** In this
    code that means:
    - An icon beside its words is a SwiftUI `Label`. An icon-only control has
      an `.accessibilityLabel` that names what it does ("Remove Ann Able")
      and a `.help` tag.
    - A value drawn as a mark (the Wood Badge pentagon, a status badge, the
      value of an `EditableChoice`) has its words in `accessibilityLabel` or
      `accessibilityValue`. A line joined with " · " is read through
      `spokenList`, with commas.
    - Page, sheet, window, and section titles are headings (`.heading(_:)`).
    - What VoiceOver hears of a step that worked, an arrival, or a count is a
      sentence built in `EagleBoardsCore` (`StepSpeech` and its neighbors),
      with a test. `Speech.say` says it, with nothing put on screen (SPEC.md
      D-14).
    - A context menu lists only what applies, with no keys (`MenuCommand`,
      HIG Context menus). With Keyboard navigation on, Tab reaches every
      control, room cards included. A new shortcut never takes a key macOS
      uses (HIG Keyboards). One that Windows has keeps its key, with Command
      for Ctrl (SPEC.md P-3), as the pages' Command-1 to Command-8 do.
    - Help and messages say click for a button and choose for a menu item.
      Menu paths read File › Export List…, and keys read Command-Return.
      Places are named (the toolbar, the inspector, Free for a Final Board)
      instead of given as directions such as top right or below, and a symbol
      is spelled out: up and down arrows, a minus sign in a circle.
13. **A command acts only on what the page shown has in view.** The inspector,
    with the selected youth's board, is beside the Event page alone; rooms are
    the Event and Rooms pages'; the event's adults are the Adults page's
    (`SchedulerPage`, tested in `SchedulerPageTests`). The other pages have no
    inspector and no next-step button, and the menus keep their items,
    dimmed, as `MenuCommand` does. A selection is kept when the operator
    leaves its page and is never acted on from a page that cannot show it:
    board commands go through `AppModel.boardYouth`, room commands through
    `selectedRoom`, and adult commands through `selectedAdults`, so a key, a
    double-click, or a drop that reaches the model from another page does
    nothing. A new page answers every question in `SchedulerPage`, and a new
    command asks one of them.

    Edit › Undo and Redo work from every page, so they bring what they
    changed into view: each undoable change passes a reveal to `AppModel`
    (`revealBoard(of:)`, `revealRooms(selecting:)`, or `revealAdults(_:)`),
    which calls `show` with the page `SchedulerPage.revealing(_:)` answers. A
    board change, linking an introducer included, lands on the Event page; a
    room change stays on the Event or Rooms page and otherwise lands on the
    Event page; marking an adult gone home or back lands on the Adults page.

## Releases

Versions are CalVer: the release date, e.g. `2026.09.22`. Pushing a tag
`v2026.09.22` runs `release.yml` in three jobs. The build job, on
`macos-latest`, refuses a tag that is not a `vYYYY.MM.DD` date, a version with
no `## 2026.09.22` section in `CHANGELOG.md`, and a commit with no passing
Build run. It then runs the tests, builds the app, checks it, and zips it as
`Eagle-Boards-2026.09.22.zip` with a `SHA256SUMS` file. The verify job, on
`macos-15`, unzips that exact file and runs `scripts/check-app.sh` on it, which
checks the bundle and launches it. The publish job creates the release as a
draft and makes it public. Each release's notes are the changelog section
(`scripts/release-notes.sh`) and a first-launch paragraph. A failure in any job
leaves nothing public; a draft left by a run that failed after creating it
has to be deleted on the Releases page before the run is repeated. A second
release on one date has no defined name yet.

The app is signed ad hoc, so on another Mac Gatekeeper stops it the first
time. It opens once someone clicks **Open Anyway** in System Settings ›
Privacy & Security after trying it. The right-click > **Open** route no
longer exists on macOS 15 and later, the versions this app supports, so the
release notes give Open Anyway. Signing with a Developer ID identity
(`SIGNING_IDENTITY=... scripts/build-app.sh`) and notarizing removes that.

### Before tagging

1. The Build workflow is green on the exact commit to tag (rule 1). The
   release workflow looks for that run and stops without it.
2. `## Unreleased` in `CHANGELOG.md` is renamed to the tag's date.
3. Run `swift package update`, read the `Package.resolved` diff and the
   release notes of `hummingbird` and `swift-nio` (the two packages that parse
   requests from the venue network), then run `swift test`.
4. In `eagleboards-shared`, run `scripts/check-drift.sh` and expect every line
   to read "same". Add a parity row to `SPEC.md`, and a line to the Stale list
   in `WEBSITE.md`, for anything that exists only on the Mac or changes what
   an operator sees (that repository's `CLAUDE.md` says both change in the
   same commit as the behavior). A new minimum macOS is covered by
   `WEBSITE.md`, and the Mac row in that repository's `README.md` states the
   minimum too, so change it in the same step. Check
   that the website's Mac page names the version about to ship.
5. Run `git log --format='%h %G?' <last tag>..HEAD` and note any commit marked
   `N`, which is unsigned. Do not rewrite history for it.
6. Build the zip as the workflow does (`VERSION=<date> scripts/build-app.sh`,
   then `ditto -c -k --keepParent "build/Eagle Boards.app"
   Eagle-Boards-<date>.zip`) and try it on a Mac that has never had Xcode:
   first launch, **Open Anyway**, and the keychain prompt for the
   SignUpGenius key. Launch it from where it was unpacked, quit, and launch it
   a second time.
7. Install it over the previous version, with the macOS firewall on and a copy
   of a synthetic data folder, and confirm a phone still reaches the sign-in
   page. Each ad hoc build has a new code identity, so this is where a
   changed firewall prompt would show.

### After publishing

1. Open the published zip, downloaded through a browser, on a Mac that has
   never had Xcode and repeat step 6. The release workflow downloads nothing
   through a browser, and only a browser download gets the quarantine mark
   that sends Gatekeeper down the Open Anyway path.
2. Add a line to the release notes saying which macOS version the zip was
   tried on, using the commands in step 2 of Rollback.

### Rollback

1. Mark the previous release Latest: `gh release edit <previous tag> --latest`.
2. Add a line to the bad release's notes naming the version to use. Read the
   notes with `gh release view <tag> --json body --jq .body`, add the line,
   and save them with `gh release edit <tag> --notes-file <file>`.
3. Fix forward with a new date tag. Never move or reuse a tag.
4. Before telling anyone to reinstall an older zip, read `CHANGELOG.md` for a
   change in the shape of the data files between the two versions (rule 4;
   `FileFormatTests` pins it), since the older app may not read what the newer
   one wrote.

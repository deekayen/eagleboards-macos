# Contributing

## Shape of the thing

A Swift package with three targets, layered so the rules can be tested
without a window or a socket:

```
  Sign-in tablet (browser)                     The Mac
        |  /  /youth_register  /adult_register       |
        |  /api/checked-in  /api/*-lookup            |  SwiftUI windows:
        |  /register-youth  /register-adult          |  Scheduler, Records,
        +----------------------+                     |  Settings, Help
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
                              |  EventNight          |  board rules, every
                              +----------+-----------+  lifecycle step
                                         |
                                  data folder on disk
```

| Target | What lives there |
| --- | --- |
| `EagleBoardsCore` | `Records.swift` (the record types), `DataFiles.swift` (the CSV and `config.properties` dialects), `BoardRules.swift` (composition rules, board suggestion, locating leaders, room timers), `EventNight.swift` (one night's state and every change to it), `SignUpGenius.swift`. No UI, no server. |
| `CheckInServer` | The web server for the tablets, and the sign-in pages in `Resources/CheckIn`. It serves those pages and the five calls they make, and nothing else. |
| `EagleBoards` | The SwiftUI app. `AppModel` holds which night is open, runs the server, and keeps the operator's work in progress. |

`EventNight` is `@MainActor` and `@Observable`. The windows read it directly;
the server hops onto the main actor to register someone. So a sign-in shows
up on the scheduler the moment it lands, with no polling, and there is only
one thread that ever changes the data.

## Build, run, verify

Needs a Mac with Apple silicon, macOS 14 or later, and Xcode (or its command
line tools) with Swift 6.

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

**Prefer pushing over re-running everything locally.** CI (`build.yml`) runs
the tests, builds the app, checks the bundle, and runs the guards
below. Run things locally to debug what CI found, or to iterate.

## The rules this code keeps

1. **CI is the acceptance gate.** Keep it green. Add a test when you fix a
   bug, and a case in `BoardEveningTests` when you change how a board is
   seated, run or torn down -- a rule with no test is a rule that comes back.
2. **Never commit participant data or secrets.** Data folders live outside
   the repository. `.gitignore` and `scripts/hooks/pre-commit` block CSVs,
   dated folders, `Master_AdultHistory*` and `config.properties`. Install the
   hook once per clone: `git config core.hooksPath scripts/hooks`.
3. **Test against synthetic data, never real data.** Tests create throwaway
   folders of made-up people. Never point the app at the real adult history
   while taking screenshots.
4. **The data files are the contract.** Both this app and the Java Eagle Board
   Scheduler read and write them, so a district can move between the two, or
   fall back to the Java app on the night. Keep column names, column order,
   ID shapes and the comma dialect exactly as `FileFormatTests` pins them.
5. **The network gets the sign-in pages and nothing more.** Every operator
   screen is a window. Anything the server returns is trimmed to what its page
   shows; no call takes a column name. `CheckInServerTests` asserts the old
   operator paths are 404. Keep it that way.
6. **Board composition rules live in two places, on purpose.** `SeatingReview`
   explains them to the operator, and asks for confirmation where a rule
   allows it. `EventNight.seatBoard` refuses the hard ones again, whatever
   called it. Both must agree:
   - **Size.** A board of review has three to six members (GTA 8.0.0.3): fewer
     refused, four to six confirmed, seven refused. A project proposal review
     is not a board of review (GTA 9.0.2.4); the district runs it with two,
     under the same ceiling.
   - **Chair is binding.** The chair's role for that board type must be
     `Chair`, and the chair must be on the board. When the qualified chairs are
     all busy, the answer is to promote someone in Records, never to hand the
     gavel to a Member.
   - **One board at a time.** An adult with a `Room` is committed to it. `N/A`
     is the Disable marker for someone gone home.
   - **Same unit.** A same-unit member is an overridable warning (this
     council forbids them; the national rule does not). A board made *entirely*
     of the youth's unit is refused (GTA 8.0.3.0 #2). Deliberately not checked
     in `seatBoard`: it is a judgement call.
7. **Lifecycle:** Registered -> Seated -> InProgress -> Completed, or
   Registered -> Postponed. Seating and starting are separate so the two phases
   can be timed apart: seating convenes the board with the paperwork while the
   youth waits (GTA 8.0.3.0 #8), and Start Review brings them in. Only an
   InProgress board can be completed. `Verified` survives on legacy records
   only; nothing sets it.
8. **Names say what things are for.** No `var1`-style names anywhere. CI
   greps for `var` followed by digits and fails.
9. **Branding is district-neutral.** The app never displays whose district
   it is.

## Releases

Versions are CalVer: the release date, e.g. `2026.09.22`. Pushing a tag
`v2026.09.22` runs `release.yml`, which builds the app, checks it
carries no data or key, and attaches `Eagle-Boards-2026.09.22.zip` to a
GitHub release.

The app is signed ad hoc, so on another Mac Gatekeeper asks for a
right-click > **Open** the first time. Signing with a Developer ID identity
(`SIGNING_IDENTITY=... scripts/build-app.sh`) and notarizing removes that.

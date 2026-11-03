# Provenance

Eagle Boards is the native Mac version of the **Eagle Board Scheduler**, a Java
application maintained at `deekayen/eagleboards-java`.

That Java application was itself reconstructed from an inherited binary. The
original was written by a third party for a Scouting district, and only its
compiled jar was ever received; the Java sources were produced by decompiling
it, then modernized. The Java repository's `PROVENANCE.md` records the method
and the checksum of the original artifact.

## What came from the Java app

This repository starts a fresh history. No Java source is carried over, and
none of the Java app's code was translated line by line. What it carries over
is behavior and interface:

- **The data files.** Column names and order, record IDs, the comma dialect
  (commas stored as `~`, line breaks as `+`), timestamp shapes, and the folder
  layout are kept exactly, so the two programs can open each other's data.
- **The board rules.** Board size, the binding chair designation, one board
  per adult, and the same-unit rule, with the Guide to Advancement references
  the Java project documented. The rule and auto-select cases are shared by
  the three versions (SPEC.md D-5): `SharedCaseTests` runs every file in
  `Tests/EagleBoardsCoreTests/Resources/cases/`, copies of
  `eagleboards-shared/cases` pinned by `test-cases.lock`. `BoardEventTests`
  mirrors the Java event test's scenarios.
- **The lifecycle.** Registered, Seated, InProgress, Completed, or Postponed,
  including the legacy `Verified` status.
- **The sign-in pages.** `Sources/CheckInServer/Resources/CheckIn` began as the
  Java app's `index.html`, `youth_register.html`, and `adult_register.html`,
  plus the public-page rules of its stylesheet. The five files are now copies of
  `eagleboards-shared/checkin`, pinned by `checkin-pages.lock` (SPEC.md D-18),
  and all three versions serve them unchanged. They call the endpoints that
  D-2 and D-18 define, which each version implements.

The scheduler, record, and settings screens, which were web pages in the Java
app, are new SwiftUI windows.

## Third-party code

| Component | License | Use |
| --- | --- | --- |
| [Hummingbird](https://github.com/hummingbird-project/hummingbird) and its SwiftNIO dependencies | Apache-2.0 | The sign-in station's web server |

`Package.resolved` pins the exact versions.

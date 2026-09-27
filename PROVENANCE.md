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
  (commas stored as `~`, line breaks as `+`), timestamp shapes and the folder
  layout are kept exactly, so the two programs can open each other's data.
- **The board rules.** Board size, the binding chair designation, one board
  per adult, and the same-unit rule, with the Guide to Advancement references
  the Java project documented. Its test cases are carried over in
  `BoardRulesTests` and `BoardEventTests`.
- **The lifecycle.** Registered, Seated, InProgress, Completed or Postponed,
  including the legacy `Verified` status.
- **The sign-in pages.** `Sources/CheckInServer/Resources/CheckIn` began as the
  Java app's `index.html`, `youth_register.html` and `adult_register.html` and
  the public-page rules of its stylesheet. They now call this app's own
  endpoints.

The scheduler, record and settings screens, which were web pages in the Java
app, are new SwiftUI windows.

## Third-party code

| Component | License | Use |
| --- | --- | --- |
| [Hummingbird](https://github.com/hummingbird-project/hummingbird) and its SwiftNIO dependencies | Apache-2.0 | The sign-in station's web server |

`Package.resolved` pins the exact versions.

# Changelog

Versions are CalVer: the release date.

## Unreleased

The first version of Eagle Boards, the native Mac version of the Java Eagle
Board Scheduler.

### How it differs from the Java app

**Operator screens are windows, not web pages.** The scheduler, the records
(the Java app's `/admin`) and the settings (`/configure`) are SwiftUI windows
on the Mac. The network serves only the sign-in pages, so someone at the door
can no longer type `/admin` and read every adult's email and phone number.

**The sign-in station exposes less.**
- The lists at the door carry names and units only.
- Email autofill no longer sends the tablet every email address on file.
  Typing an address looks up that one address, by POST, and returns only the
  fields the form fills in.
- Nothing on the network takes a column name, so no request can ask for more.

**The scheduler updates the moment someone signs in.** No polling.

**The scheduler is a Mac window, not a grid of panels.** A sidebar lists the
youth waiting, on boards and finished, the adults, and every room with its
timer; the inspector follows the selected youth. The board proposed for a
waiting youth is shown and changed there (add, remove, or drag adults onto it)
instead of with checkboxes in a separate list, and a board drawn up by hand is
kept per youth. One Next Step button, Command-Return and double-click take a
youth to Seat Board, Start Review or Complete. Every action is in the Board,
Adult and Room menus and in context menus. A waiting youth can be dragged onto
a free room. Messages that used to vanish from the bottom of the window are
now alerts that say what failed, or live in the inspector (who to fetch for a
youth). Link and Disable no longer ask first; Unlink and Enable undo them.

**Seat Board shows everything at once.** Every reason a board cannot be
seated is listed together instead of one alert at a time, and each warning
(same-unit member, a fourth member, a room of the other kind) takes its own
tick. A member unavailable for that board type is refused whatever their
position in the list; the Java app caught one only if they came before the
chair.

**Signing in again is harmless.**
- A youth who signs in twice keeps their place in line. The Java app issued a
  new P or W number every time.
- An adult who signs in twice is recorded once in the adult history for the
  night.
- A first and last name are required, and a new youth must choose a board
  type.
- Emails match regardless of case, and `NONE` never matches anyone.
- Choosing District, Council or Community after autofill disables Unit #, as
  it does when chosen by hand.

**SignUpGenius import fixes.**
- Phone numbers are formatted from their digits. The Java app mixed the
  punctuation of the original into the result.
- Full surnames are kept. The Java app kept only the first word.
- "Post" units are no longer read as Pack.
- A "Project Proposal Review" slot is a project review. The Java app counted
  any slot containing "review" as a final board.
- A sign-up is found on its first day. The Java app compared the date with a
  date-and-time string and missed it.
- The API key is kept in the macOS keychain instead of on a command line.

**Apple silicon only.** Eagle Boards runs on Macs with Apple silicon (M1 or
later) and macOS 14 or later. Intel Macs are not supported.

**New:**
- A QR code for the sign-in address.
- Copy rooms from an earlier night.
- The Mac is kept awake while serving, and Eagle Boards asks before quitting.
- Deleting a youth or adult whose board is active is refused.
- Data files are written atomically, so a crash mid-save cannot truncate one.
- The app icon is the cast eagle from the Eagle Scout medal, as on the
  Windows version.

**Not carried over:**
- The `-prereg` import of the district website's CSV, which SignUpGenius
  replaced.
- `-bind`. The station listens on every interface and shows each address.

# Changelog

Versions are CalVer: the release date.

## Unreleased

**Every youth in one list** (SPEC.md O-3, amended). The Event page lists the
youth stacked Waiting, On a Board and Finished, each with its count, beside the
room cards, instead of a sidebar entry per group that had to be picked before a
youth could be found. The search looks through all three groups. A waiting
youth still drags onto a free room.

**No sidebar** (P-1, P-6, D-17), as in the Java and Windows versions: the page
has the window's whole width. On the Event page the youth list is a 320-point
column, as on Windows, and the room cards take the rest; drag the line between
them to widen the list, and it stays that wide. The View menu chooses the page,
with a check on the one shown. Add Room is in the Room menu (Shift-Command-N)
and on a room card's right-click menu. Help › Donate… opens the ways to support the project, with the Venmo QR
code, in a window of its own; it replaces the Donate button at the sidebar's
foot and the Help menu's list of links.

**The records are pages, edited in place** (P-6). The Records window is
gone. Its lists are pages in the View menu beside Event (Option-Command-1 to
5), and every value on them is changed where it is shown: click a name, unit or
note to type in it, or a value with a small chevron to choose from a menu.
Undo takes a change back. **Youth** is every youth, with their board, status,
result, chair, members and notes; a result recorded against the wrong youth is
corrected there. **People** is tonight's adults, where someone is promoted to
Chair. **Pre-Registered** and **Adult History** are the SignUpGenius sign-ups
and every adult who has ever signed in; Adult History's search looks through
names, emails and units, and its Last Event column has a check for those
signed in today. File › Export List… saves the page's list; right-click a
record to delete it. The records window's Rooms list is left to the Event
page's room cards, which already rename, switch, move and remove rooms.

**Add an adult by hand.** Adult › Add Adult…, the Add Adult button at the foot
of People, or a double-click below the last row signs in an adult who would
rather not use the tablet, through the tablet's own sign-in. Its search fills
the form in from the adult history, and a role left at As Last Time keeps the
one on file. On Adult History, double-click someone, or choose Sign In for
Today, to put them on tonight's list.

**One member per line on the room cards**, as on Windows, in full, so a name is
never cut off.

**One status palette, and a clock per timer state** (SPEC.md D-13). The
status badges and room timers take the colors all three versions now share,
from Monokai Pro's hues, checked for contrast and color blindness in light and
dark: Seated yellow, In review cyan, Completed purple, Waiting and Postponed
gray. A room timer shows a stopwatch on time, a timer on an orange tint when it
runs long, and an alarm clock on a solid pink-red fill when it is overdue.
Running long and overdue used to share one warning symbol in orange and red,
which look alike to many color-blind operators. Increase Contrast adds a border
to each. Settings and Help say "running long" and "overdue" instead of yellow
and red, and so does the notification.

**Badges say Waiting and In review** (D-13), as the Java and Windows versions
do, instead of Registered and In Progress. So do VoiceOver, the Records window
and the alerts that name a status. The data files still store `Registered` and
`InProgress`, so the Java app reads them as before. The Records window's Status
menu no longer offers the legacy Verified, which nothing sets and which would
have read Waiting a second time.

**Status colors are not settings** (D-19). The twelve `*Color` keys are gone
from `config.properties`; a file that still has them opens, and saving leaves
them out.

**No youth phone numbers** (SPEC.md D-8). Nothing used one, so the youth
sign-in no longer asks for it or keeps one sent by an older cached page, a
SignUpGenius import no longer copies it, and the email lookup, the Records
window and the board results report no longer show or export it. A number
already on file stays there, unchanged by signing in again, and the `Phone`
column stays in the youth data files. Adults' phone numbers are unchanged.
A youth list saved from the Records window now leaves out a birthdate on file
too (D-7).

**Room cards work with VoiceOver.** A card said it was a button, but only a
mouse click selected it. Pressing it (VO-Space) now selects the room and its
youth, and the board's next step, Start Review or Complete, is in its
actions (VO-Command-Space), as a double click takes it.

## 2026.09.25

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

**Undo.** Edit › Undo takes back a board step (seat, start, complete, postpone,
reset), Disable and Enable, Link and Unlink, and every room change, so Reset,
Postpone and Remove Room no longer ask first. `EventNight.restoreBoard` puts a
board back and refuses when its room or a member has been given to another
board since, so undo can never put an adult on two boards.

**While the window is behind.** The Dock icon shows how many are waiting, and a
notification says when a room passes its red time. Window › Sign-In Code shows
the sign-in QR code large, for a second display or a projector.

**Status colors follow the system.** Badges use a symbol and a system color
that reads in dark mode. The Java app's status colors stay in
`config.properties`, unchanged, but the Mac app no longer offers to edit them.
(Superseded by the shared palette; see Unreleased.)

**Boards can be picked by hand.** Settings › General can start each waiting
youth with an empty board instead of a proposal. The inspector's free adults
can be searched and added with a click.

**Events, not nights.** Board events are not always in the evening, so the
app says "event" and "today" where it said "night" and "tonight". The data
files and folder names are unchanged.

**Records** has a sidebar, an inspector you can hide, and File › Open Recent
Event.

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
  event.
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
- Copy rooms from an earlier event.
- The Mac is kept awake while serving, and Eagle Boards asks before quitting.
- Deleting a youth or adult whose board is active is refused.
- Data files are written atomically, so a crash mid-save cannot truncate one.
- The app icon is the cast eagle from the Eagle Scout medal, as on the
  Windows version.

**Not carried over:**
- The `-prereg` import of the district website's CSV, which SignUpGenius
  replaced.
- `-bind`. The station listens on every interface and shows each address.

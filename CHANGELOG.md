# Changelog

Versions are CalVer: the release date.

## Unreleased

**Eagle Boards needs macOS 15 or later** (this changes the requirement from
macOS 14, which is no longer supported). GitHub retired its macOS 14 runner on
2026-11-02, and the maintainer's Mac runs a newer macOS, so macOS 14 cannot be
tested. On macOS 15 and macOS 26 the automated checks run the tests and
launch the built app; on macOS 15 they also launch the published zip itself.
The maintainer runs the app on macOS 27.

**The pages are on Command-1 to Command-8**, the keys Windows gives them with
Ctrl, in place of Option-Command-1 to 8. Option-Command-8 was also the macOS
Zoom shortcut. Window › Scheduler and Window › Sign-In Code gave up
Command-1 and Command-3; they have no keys now.

**Start Over** replaces Suggest a Board in the Board menu and the inspector
(SPEC.md D-12). **Mark Gone Home** and **Mark Back** replace Enable for Today
and Disable for Today in the Adult menu. The right-click menu of a youth, an
adult, or a room lists only what can be done to them now.

**Remove Room… asks first**, naming the room, and **Edit › Undo** still adds it
back.

**Choose the sign-in network.** The sign-in station used to answer on every
network the Mac was on, a VPN, a virtual machine's bridge, or a phone hotspot
included. It now serves the Wi-Fi unless you choose another in Settings ›
General › Network, which appears when the Mac is on more than one network.
Every Network brings back the old behavior.

**A sign-in station that fails to start lets the Mac sleep again.** It used to
keep the Mac awake until Eagle Boards quit. The quit confirmation now says each
change is written to disk when it is made.

**Overdue notices show while Eagle Boards is in front**, for 10 seconds. They
used to appear only behind another app. Behind another app, the style set for
Eagle Boards in System Settings › Notifications decides whether one stays, and
Settings › Timers shows that style and opens System Settings. A notice names
the youth in full.

**VoiceOver hears what happens.** VoiceOver announces a step and its Undo, a
sign-in at the door, a room turning running long or overdue, and the count of
what a search found. Each row and room card reads as one item. The sentences are
tested as text; nobody has yet listened to them through VoiceOver.

**Start Review names only whoever introduces the youth** (SPEC.md D-23), on a
board of review; a project proposal review has no introduction and starts at
once. The sign-in pages at the door draw the youth and adult tiles alike, return
to the welcome page after a sign-in, and list a youth for the adult form only
when they are here for a board of review.

**A proposed board follows its room's use** (D-24). Switching a free room from
Final Board to Proposal Review, or back, no longer leaves a proposal in it for
the other kind of board.

**Names with a comma stay whole.** A member such as "Lysander Whitmore, Jr."
was listed as two people on a room card and in the Rooms and Results pages, and
Change Members opened empty after the app was restarted. Both are fixed.

**The sign-in pages refuse a post from another web site.** A page on another
site could make a browser on the venue network send a sign-in to the Mac; the
Mac now answers it with 403.

**A name with an unusual line break can no longer split into several people.**
A name sent from the tablet holding a line-break character other than Return
and Line Feed (U+000B, U+000C, U+0085, U+2028, U+2029) read back as two or three
people, in the adult history too. Each is stored as `+` now.

**A data folder that cannot be read stops the open.** A file that existed but
could not be read, or a link pointing at an unmounted drive, was treated as
missing, and opening the event started a new, empty adult history over it.
Eagle Boards now shows the existing alert and opens nothing.

**Adults sort by name as people read it.** "de Silva" no longer lands after
"Zimmer" in the adult pickers, and Start Over in the Add
Adult sheet no longer keeps the last person's Wood Badge choice or error.

**The SignUpGenius key survives a refused save.** Saving a key deleted the old
one first, so a locked keychain or a denied prompt lost a key that worked.
It is updated in place now. An import that finishes after another event was
opened is dropped, and a second import started during the first returns at once.
The app is signed ad hoc, so after you update, macOS asks once for access to the
key in your keychain; click **Always Allow**.

**The app opens on a Mac that did not build it.** It links a Swift library that
was found only through the Xcode that built the app, so a Mac without that
Xcode could stop at launch with "Library not loaded". The library is inside the
app now, and CI checks the bundle. macOS's prompts for the Documents, Downloads,
and removable volume folders say why Eagle Boards asks.

**License notices are in the app**, at Contents/Resources/THIRD-PARTY-NOTICES.txt:
this project's LICENSE and NOTICE, then those of every package in
`Package.resolved`.

**Help says where the data goes.** Its Your data section, a SignUpGenius
section with the key steps, and an If something goes wrong section join the
README's, and the welcome screen points at Your data. The README now says how
to download and open the app.

## 2026.09.28

**Fill the Rest** (SPEC.md D-12), beside Suggest a Board in the inspector and
in the Board menu: keeps the adults you put on the board and adds a chair, if
none of them may chair it, and members up to the number needed, chosen as a
suggestion would choose them. Suggest a Board still replaces the whole board.
Seat Board… moves to the inspector's bottom row, beside Postpone.

**Every youth in one list** (SPEC.md O-3, amended). The Event page lists the
youth stacked Waiting, On a Board, and Finished, each with its count, beside the
room cards, instead of a sidebar entry per group that had to be picked before a
youth could be found. A waiting youth still drags onto a free room.

**Find a person's room** (D-21). On the Event page the search finds a person,
youth or adult, not a youth in the list: the room cards narrow to the rooms
holding a match, or a room by that name, and a line above them says where
anyone found in no room is (*is waiting*, *isn't on a board*, *has gone home*,
*has finished*, *was postponed*), or that no one by that name has signed in.
Return opens the first room found, or the youth.

**Approved Proposals** (D-22), a page after Rooms (Option-Command-8): every
project proposal approved at an earlier event in the data folder, however long
ago, for a youth who comes to their board without the signed page. It shows
who, their unit, when, the chair, the other members, and the notes, never an
email, phone number, or birthdate; says which earlier events it read and names
any it couldn't; and is read only.

**The Adult History CSV no longer freezes the app.** After scrolling a long
history, switching pages took seconds to minutes; the history, and Approved
Proposals, are now plain AppKit tables.

**No sidebar** (P-1, P-6, D-17), as in the Java and Windows versions: the page
has the window's whole width. On the Event page the youth list is a 320-point
column, as on Windows, and the room cards take the rest; drag the line between
them to widen the list, and it stays that wide. The View menu chooses the page,
with a check on the one shown. Add Room is in the Room menu (Shift-Command-N)
and on a room card's right-click menu. Help › Donate… opens the ways to support the project, with the Venmo QR
code, in a window of its own; it replaces the Donate button at the sidebar's
foot and the Help menu's list of links.

**Every table a page, edited in place** (P-6), as on Windows. The Records
window is gone. The View menu has Event, then Results, Adults, Youth,
Pre-Registered, Adult History CSV, and Rooms (Option-Command-1 to 7), and a value is
changed where it is shown: click a name, unit, or note to type in it, or a value
with a small chevron to choose from a menu. A changed cell is saved as it is
left and stays off the Undo stack. Who sits on a board and which room anyone is
in stay read-only; they change through the Event page's steps. So does a
youth's status, read-only on every page, so nobody is left seated without a
room and members, or finished while holding one. A cell still open when the page is left is
saved. **Results** is the boards, where a result or its notes is corrected.
**Adults** is tonight's adults, where someone is promoted to Chair and Wood
Badge is a Yes/No choice showing the mark; a change to an adult's name, unit,
contact, or roles reaches the adult history too. **Adult History CSV** is every
adult who has ever signed in, read-only; its search looks through names, emails,
and units, and its Last Event column has a check for those signed in today. **Rooms** changes what
a room is used for, with Add Room at its foot. File › Export List… saves the
page's list; right-click a record to delete it.

**Add an adult by hand.** Adult › Add Adult…, the Add Adult button at the foot
of Adults, or a double-click below the last row signs in an adult who would
rather not use the tablet, through the tablet's own sign-in. Its search fills
the form in from the adult history, and a role left at As Last Time keeps the
one on file. On Adult History CSV, double-click someone, or choose Sign In for
Today, to put them on tonight's list.

**One member per line on the room cards**, as on Windows, in full, so a name is
never cut off.

**One status palette, and a clock per timer state** (SPEC.md D-13). The
status badges and room timers take the colors all three versions now share,
from Monokai Pro's hues, checked for contrast and color blindness in light and
dark: Seated yellow, In review cyan, Completed purple, and Waiting and
Postponed gray. A room timer shows a stopwatch on time, a timer on an orange
tint when it runs long, and an alarm clock on a solid pink-red fill when it is
overdue.
Running long and overdue used to share one warning symbol in orange and red,
which look alike to many color-blind operators. Increase Contrast adds a border
to each. Settings, Help, and the notification say "running long" and
"overdue" instead of yellow and red.

**Badges say Waiting and In review** (D-13), as the Java and Windows versions
do, instead of Registered and In Progress. So do VoiceOver, the Records window,
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
window, and the board results report no longer show or export it. A number
already on file stays there, unchanged by signing in again, and the `Phone`
column stays in the youth data files. Adults keep their phone numbers.
A youth list saved from the Records window now leaves out a birthdate on file
too (D-7).

**A status badge never wraps.** In a narrow youth list the name gives way,
cut short, instead of the badge and timer breaking onto two lines.

**Room cards work with VoiceOver.** A card said it was a button, but only a
mouse click selected it. Pressing it (VO-Space) now selects the room and its
youth, and the board's next step, Start Review or Complete, is in its
actions (VO-Command-Space), as a double click takes it.

## 2026.09.25

The first version of Eagle Boards, the native Mac version of the Java Eagle
Board Scheduler.

### How it differs from the Java app

**Operator screens are windows, not web pages.** The scheduler, the records
(the Java app's `/admin`), and the settings (`/configure`) are SwiftUI windows
on the Mac. The network serves only the sign-in pages, so someone at the door
can no longer type `/admin` and read every adult's email and phone number.

**The sign-in station exposes less.**
- The lists at the door contain names and units only.
- Email autofill no longer sends the tablet every email address on file.
  Typing an address looks up that one address, by POST, and returns only the
  fields the form fills in.
- Nothing on the network takes a column name, so no request can ask for more.

**The scheduler updates the moment someone signs in.** No polling.

**The scheduler is a Mac window, not a grid of panels.** A sidebar lists the
youth (waiting, on boards, and finished), the adults, and every room with its
timer; the inspector follows the selected youth. The board proposed for a
waiting youth is shown and changed there (add, remove, or drag adults onto it)
instead of with checkboxes in a separate list, and a board drawn up by hand is
kept per youth. One Next Step button, Command-Return, and double-click take a
youth to Seat Board, Start Review, or Complete. Every action is in the Board,
Adult, and Room menus and in context menus. A waiting youth can be dragged onto
a free room. Messages that used to vanish from the bottom of the window are
now alerts that say what failed, or live in the inspector (who to fetch for a
youth). Link and Disable no longer ask first; Unlink and Enable undo them.

**Undo.** Edit › Undo takes back a board step (seat, start, complete, postpone,
reset), Disable and Enable, Link and Unlink, and every room change, so Reset,
Postpone, and Remove Room no longer ask first. `EventNight.restoreBoard` puts a
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
files and folder names stay as they were.

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
- Choosing District, Council, or Community after autofill disables Unit #, as
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

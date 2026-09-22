# Eagle Boards

A Mac app for the check-in desk and room assignments on an Eagle Scout board
of review night. Youth and adults sign themselves in on a tablet at the door,
using its web browser. You sit at the Mac, put each youth with a board and a
room, and record the result when they come out.

It runs on one Mac at the event. It needs no internet, only a Wi-Fi network
that the tablet and the Mac are both on.

This is the native Mac version of the Java
[Eagle Board Scheduler](https://github.com/deekayen/eagleboards). It reads and
writes the same data files, so a district can switch between them.

**Running an event night? This page is the whole manual.** The same guide is
in the app under **Help › Eagle Boards Help**.

## Before the first night

You need three things:

1. **A Mac** running macOS 14 Sonoma or later, with Eagle Boards on it.
2. **A tablet or laptop for the door**, with a web browser, on the same Wi-Fi.
3. **Your room list**: which rooms you have, and whether each is used for
   project proposal reviews or for final boards.

The first time Eagle Boards opens, it asks where to keep its data. Choose
**Use Documents › Eagle Boards**, or a folder of your own. If you used the
Java Eagle Board Scheduler, choose the folder it ran in, the one holding
`Master_AdultHistory.csv` and the dated folders. Both programs read the same
files.

That folder holds personal information, some of it about minors. Keep it
private.

## Starting up

Open Eagle Boards. It opens tonight and starts the sign-in station at once.

If macOS asks whether Eagle Boards may accept incoming network connections,
click **Allow**. Otherwise the tablet cannot reach it.

Click the green **Sign-in** address at the top left of the window. Scan the QR
code with the tablet's camera, or type the address into the tablet's browser.

Only the sign-in pages are on the network. The scheduler, the records and the
settings stay on the Mac, so nobody at the door can look up anyone's details.

## Set up your rooms

Do this before anyone arrives. A board cannot be seated without a room.

In the **Rooms** panel, click **+** and add each room, marking it **Final
Board** or **Proposal Review** by what it is used for tonight. After the first
night, **Copy Rooms From** brings back an earlier night's list.

To hold two proposal reviews in one room, add it twice, e.g. `200A` and `200B`.

## The night, step by step

### 1. People sign in

At the tablet, a youth taps **I am a Youth** and an adult taps **I am 21+**.
Each fills in the form. Youth who pre-registered on SignUpGenius, and adults
who have served before, are recognized by email, and the rest of the form
fills itself in.

Each person appears on the Mac the moment they register. Youth are numbered
`P1, P2…` if they pre-registered and `W1, W2…` if they walked in. Pre-registered
youth are listed ahead of walk-ins.

### 2. Check the paperwork

Check each youth's paperwork as they sign in. If it is not in order, select
them and press **Postpone**.

### 3. Seat a board

Select a youth. Eagle Boards proposes a board: a chair, enough members, and a
free room of the right kind. It never picks adults from the youth's own unit.

Change the board with the checkboxes in **Adult Board Members**. Checked adults
stay checked while you click around. **Clear** empties the list.

Press **Seat Board**. The sheet lists anything that stops the board, such as
too few members, no qualified chair, or someone already on another board. It
also lists anything worth a second look, and each of those needs its own tick.
Choose the chair and press **Seat Board**.

The members now have the room and the paperwork. The youth waits outside.

### 4. Start the review

When the members have finished reading, press **Start Review**. The
confirmation lists the youth's leader and parents, if they signed in, so they
can be fetched too.

### 5. Complete

When the board has finished, press **Complete**, choose the result, and add
any notes. The room and the members are free for the next board.

## Rules the scheduler keeps

- **Board size.** A final board of review has three to six members (Guide to
  Advancement 8.0.0.3). Three is the norm, four to six asks you to confirm, and
  seven is refused. A project proposal review has two to six.
- **The chair.** Only an adult whose role for that kind of board is **Chair**
  may chair it. When the qualified chairs are all busy, promote someone in the
  **Records** window. Nobody is made chair by accident.
- **One board at a time.** An adult on a board cannot be put on another.
  **Disable** takes someone out of the pool for the night, for example when
  they have gone home. **Enable** brings them back.
- **Same unit.** This council does not allow adults from the youth's own unit
  on the board. You may override that, but a board must still have at least one
  member from outside the unit (8.0.3.0).

## Room timers

Each busy room shows the minutes since its last step. While a board convenes,
the card turns red after 30 minutes. Once the review starts, a final board
turns yellow at 30 minutes and red at 45. A proposal review turns yellow at 25
and red at 40. They are prompts, not limits. Change them in **Settings ›
Timers**.

## SignUpGenius

Put the district's SignUpGenius API key in **Settings › SignUpGenius**.
Eagle Boards keeps it in your macOS keychain. When tonight opens, it imports
the sign-up: youth become pre-registrations and adults join the history. Use
**File › Import Sign-Ups** to do it again.

## After the night

**File › Export Board Results** saves the night as a spreadsheet (CSV).
Everything is saved as it happens; there is nothing to save before quitting.

## If something goes wrong

| Problem | What to do |
| --- | --- |
| The tablet cannot open the address | Check both are on the same Wi-Fi. Click the sign-in address and try another address listed there. Check that Eagle Boards is allowed in System Settings › Network › Firewall. |
| "Port 8080 is already in use" | Quit the other program (the Java Eagle Board Scheduler uses 8080 too), or change the port in Settings › General. |
| "Not qualified to chair" | Promote someone: open Records › Adults, select them, and set their Final or Project role to Chair. |
| A board was seated by mistake | Select the youth and press **Reset**. |

## For developers

See [CONTRIBUTING.md](CONTRIBUTING.md) for building, testing and the rules
this code keeps. [PROVENANCE.md](PROVENANCE.md) records where it came from.
Licensed under the Apache License 2.0; see [LICENSE](LICENSE) and
[NOTICE](NOTICE).

import EagleBoardsCore
import SwiftUI

/// The operator's guide, kept short enough to read during the event, with a
/// search that narrows it to the paragraphs holding every word typed.
struct HelpView: View {
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        let sections = HelpSection.matching(search, in: Self.guide)
        Group {
            if sections.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Headings for VoiceOver's rotor, at the levels Windows' Help uses.
                        Text("Running an Eagle Boards event").font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityHeading(.h1)
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.title).font(.title2.bold())
                                    .accessibilityAddTraits(.isHeader)
                                    .accessibilityHeading(.h2)
                                ForEach(section.items, id: \.self) { bullet($0) }
                            }
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 720, alignment: .leading)
                    .textSelection(.enabled)
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search Help")
        .modifier(SearchFocus(isFocused: $searchFocused))
        // Edit › Find… in this window goes to this search.
        .focusedSceneValue(\.helpSearch, HelpSearchAction { startToolbarSearch($searchFocused) })
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Each paragraph is its own element already; a spoken bullet
            // before every one is noise.
            Text("•").accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    static let guide = [
        HelpSection("Before anyone arrives", [
            "Open Eagle Boards on the admin Mac. It opens today's event and starts the sign-in station.",
            "Click the sign-in status in the toolbar. Scan the QR code with the tablet at the door, or type the address into its browser. The tablet must be on the same Wi-Fi as the Mac. If the Mac is on more than one network, choose the tablet's from the Network menu shown with the code.",
            "For a second display or a projector by the door, choose Window › Sign-In Code and make it as large as you like. It shows the same network's code.",
            "Add today's rooms with Room › Add Room… (Shift-Command-N), marking each Final Board or Proposal Review by what it is used for today. After the first event, Room › Copy Rooms From brings back last month's rooms.",
            "To hold two proposal reviews in one room, add it twice, for example 200A and 200B.",
            "To rename a room, right-click its card and choose Rename…. A board already in it moves with it; nobody is reseated.",
            "If macOS asks whether Eagle Boards may accept incoming network connections, click Allow. Otherwise the tablet cannot reach it.",
        ]),
        HelpSection("People sign in", [
            "At the tablet, a youth taps I am a youth and an adult taps I am 21 or older. Each fills in the form.",
            "People who pre-registered on SignUpGenius, and adults who have served before, are recognized by email and their form fills itself in.",
            "They appear in the scheduler the moment they register. Youth are numbered P1, P2… if they pre-registered and W1, W2… if they walked in, and the list keeps pre-registered youth ahead of walk-ins.",
            "An adult who would rather not use the tablet can be signed in on the Mac: choose Adult › Add Adult… (Command-N), or click Add Adult… at the foot of the Adults page. Search the adult history to fill the form in for someone who has served before; Return in the search fills it in from the only match, or goes to the matches to choose one. On the Adult History CSV page, double-click someone, or select them and choose Adult › Sign In for Today, to sign them in for today.",
            "Check the paperwork as youth sign in. If it is not in order, select them and choose Board › Postpone. Edit › Undo brings them back.",
        ]),
        HelpSection("Seat a board", [
            "Event, the first page in the View menu, lists every youth in one column (Waiting, On a Board, then Finished, each with its count), with the room cards filling the rest of the window, so every room and its timer stay in view. Drag the line between them to widen the list. The inspector follows the selected youth on every page; View › Show Inspector brings it back if it is hidden.",
            "Click a room card, or Tab to the cards, and the arrow keys move from room to room. Return takes the selected room's next step, as a double-click on its card does.",
            "To find which room someone is in, type part of their name, youth or adult, in the toolbar's search field; Edit › Find… (Command-F) puts the cursor there. The room cards narrow to the rooms holding a match, or a room by that name, and a note at the top of the room cards says where anyone found in no room is: is waiting, isn't on a board, has gone home, has finished or was postponed. Return opens the first room found, or the youth. Clear the search to see every room again.",
            "Select a waiting youth. The inspector proposes a board: a chair, enough members, and a free room of the right kind. It never picks adults from the youth's own unit. It picks with the whole waiting line in mind: it keeps adults who can chair free for the boards still to come, and uses adults whose troop rules them out for youth still waiting. If there aren't enough adults to do that it still proposes the best board it can. The member who will chair it reads Chair; anyone else on it who may chair reads Can Chair.",
            "Change who sits on the board in the inspector: click someone under Free for a Final Board, or Free for a Proposal Review, to add them (type in Find an adult to narrow the list, and press Return to add the first one), and the Remove button (a minus sign in a circle) takes them off. On the Adults page you can also Command-click several adults and choose Adult › Add to Board (Command-B), or drag them onto the board. To hand the chair to someone who reads Can Chair, right-click them and choose Make Chair, choose them from Board › Chair, or select them on the Adults page and choose Adult › Make Chair. Fill the Rest keeps who you chose and adds a chair, if none of them can chair it, and members up to the number needed; Start Over replaces the whole board with a proposal.",
            "Until you change it, the proposed board keeps up with the event: when an adult signs in, goes home or comes back, or leaves a board, it is proposed again. Choosing its room is not a change, and it stays in the room you chose while that room is free. Once you take someone off, add someone, use Fill the Rest or Clear Board, or make someone else chair, the board is yours, kept while you look at other youth.",
            "To choose every board yourself, set Settings › General › When you select a waiting youth to Start with an empty board. Selecting a youth then picks only a free room.",
            "Press Seat Board… in the inspector or the toolbar, press Command-Return, or double-click the youth. You can also drag a waiting youth onto a free room's card. The sheet lists anything that stops the board (too few or too many members, no qualified chair, someone already on another board) and anything worth a second look, each of which needs its own tick. While the sheet is open, the board stays as you are checking it, even if someone signs in.",
            "Choose the chair. The sheet starts with the board's chair from the inspector, and offers only members whose role for this kind of board is Chair. If none is free, promote someone on the Adults page: click their Final Board Role or Proposal Review Role and choose Chair.",
            "Seating gives the members the room and the paperwork. The youth waits outside.",
            "To change who sits on a seated board, before or after the review starts, select the youth and press Change Members… in the inspector, or choose Board › Change Members…. The sheet checks the board the same way Seat Board… does. The room's timer keeps running.",
        ]),
        HelpSection("Start the review", [
            "When the members have finished reading, select the youth and press Start Review (Command-Return again). For a board of review, the confirmation names whom to fetch to introduce the youth to the board and where they are, even on another board: the adult linked to them, or if no one is, their leader. A project review has no introduction, so it starts at once; Edit › Undo takes it back.",
            "At sign-in, adults can say \"No thanks\" to one kind of board (they are never seated on it), whether today counts toward a Wood Badge ticket item (marked with a small five-colored pentagon next to their name), and which youth they will introduce to their board: usually the youth's Scoutmaster, or a leader standing in, and not a parent unless they are also the Scoutmaster. Proposed boards favor those who came to serve on any board.",
            "If the adult introducing a youth did not say so at sign-in, select the youth and use Link an Adult under With Them in the inspector, which lists the adults from the youth's unit first. To unlink them, right-click them there or choose them from Board › Unlink Introducer. On the Adults page, with the youth still selected, Adult › Introduces and the youth's name links the selected adult, or unlinks them if it has a check.",
        ]),
        HelpSection("Complete", [
            "When the board has finished, press Complete… (Command-Return), choose the result and add any notes.",
            "The room and the members are freed for the next board. The inspector lists the youth's leader and parents so someone can find them.",
        ]),
        HelpSection("The records", [
            "The other pages in the View menu are the tables the event keeps, and their values are changed in place: click a name, unit or note to type in it, or a value with up and down arrows beside it to choose from a menu. A change is saved when you press Return or leave the cell. It is not on Edit › Undo, which is for the Event page's steps; change the cell back instead. Who sits on a board and which room someone is in are never typed in: they change on the Event page. Nor is a youth's status: it is read-only on every page, and changes only through the Event page's steps (Seat Board, Start Review, Complete, Postpone, Reset Board and Undo), which take and free a room and its members.",
            "Click a column heading to sort a page by it, or choose View › Sort By. The toolbar's search field narrows the page, and Return in it goes to the first row found.",
            "Results: every board and its result. Correct a result or its notes here. Double-click a board, or choose Board › Show on Event Page, to see it on the Event page.",
            "Adults: the event's adults. Promote someone to Chair, mark Wood Badge, or fix a name. Add Adult… at the foot signs someone in by hand.",
            "Youth: every youth who signed in, in sign-in order. Double-click one, or choose Board › Show on Event Page, to see them on the Event page.",
            "Pre-Registered: the youth who signed up on SignUpGenius for today.",
            "Adult History CSV: every adult who has ever signed in, across events, read-only and searched by name, email or unit. Last Event has a check for those signed in today; double-click someone, or choose Adult › Sign In for Today, to sign them in for today. A change to an adult's name, unit, contact or roles on the Adults page is made here too, so someone promoted to Chair today is a chair next time. Wood Badge is for today only.",
            "Rooms: what each room is used for today, and whose board is in it. Double-click a room, or right-click it and choose Show on Event Page, to see its card on the Event page. Add Room… at the foot adds one, and Delete removes a free one; Edit › Undo puts it back.",
            "Approved Proposals: every project proposal approved at an earlier event in the data folder, however long ago, for a youth who comes without the signed page: who, their unit, when, the chair and the other members. Read only; the page's first line says which events were read.",
            "To delete a youth, a pre-registration, or an adult, select them and press Delete or choose Edit › Delete, or right-click them; that asks first, since Undo cannot bring them back. File › Export List… (Shift-Command-E) saves the page's list as a spreadsheet.",
        ]),
        HelpSection("Board sizes", [
            "A final board of review has three to six members (Guide to Advancement 8.0.0.3). Three is the norm; four to six asks you to confirm; seven is refused.",
            "A project proposal review has two to six. Two is the norm.",
            "This council does not allow adults from the youth's own unit on the board. You may override that, but a board must still have at least one member from outside the unit (8.0.3.0).",
        ]),
        HelpSection("Room timers", [
            "The Dock icon shows how many youth are waiting, and a notification says when a room goes overdue; macOS asks once whether to allow notifications, after the first board is seated. Both keep going with the scheduler window closed.",
            "With Eagle Boards in front, the notification goes away after 10 seconds. Behind another app, it stays on screen until you close it if Eagle Boards is set to Alerts in System Settings › Notifications; with Banners it goes away on its own. Settings › Timers shows the style chosen there; to change it, click Open System Settings.",
            "Each busy room shows the minutes since its last step, with a stopwatch. While a board convenes it goes overdue after 30 minutes. Once the review starts, a final board runs long at 30 and is overdue at 45; a proposal review at 25 and 40. Running long is a timer on an orange tint and overdue an alarm clock on a solid pink-red fill, so they differ in shape and lightness, not only color.",
            "They are prompts, not limits. Change them in Settings › Timers.",
            "VoiceOver announces a room once as it turns running long, and again as it turns overdue.",
        ]),
        HelpSection("Menus", [
            "Every action is in the Board, Adult and Room menus, dimmed when it does not apply. The right-click menu of a youth, an adult or a room lists only what can be done to them now; a youth's starts with their next step.",
            "Edit › Undo (Command-Z) takes back the last step: seating, starting, completing, postponing or resetting a board, changing its members, marking an adult gone home or back, linking, and adding, copying, removing, renaming or swapping rooms. It is refused if the room or a member has been given to another board since.",
            "Board › Locate Leader and Parents (Command-L) shows the inspector and scrolls it to With Them: who introduces the selected youth, then their leader and parents, with where each one is.",
            "Board › Reset Board undoes seating: the youth waits again and the room and members are freed.",
            "Adult › Mark Gone Home takes adults out of the pool when they leave, and Adult › Mark Back brings them back if they return.",
            "Room › Move Board to Another Room… moves a board, or swaps two boards.",
            "View › Event, Results, Adults, Youth, Pre-Registered, Adult History CSV, Rooms, and Approved Proposals (Command-1 to Command-8) choose the page; the one shown has a check. View › Sort By sorts a table page by a column, either way, as a click on its heading does.",
            "Window › Scheduler and Window › Sign-In Code bring those windows back once closed, and so does the Dock icon's menu (Control-click it). Choosing a page from the View menu also brings back the scheduler.",
            "File › Export Board Results saves every board and its result as a spreadsheet; File › Export List… saves the page's list.",
            "File › Restart Sign-In Station starts the sign-in station again after it stopped with an error, for example once another program has let go of its port. File › Open Sign-In Page in Browser opens the sign-in page on this Mac.",
        ]),
        // The key contract: every key the app answers, changed with the keys.
        HelpSection("Keyboard shortcuts", [
            "These keys work on every page. The next three sections list the keys for the Event page, a table page, and a sheet. To move to every control with Tab, turn on Keyboard navigation in System Settings › Keyboard.",
            "Command-Return takes the selected youth's next step: Seat Board…, Start Review, or Complete….",
            "Command-Z undoes the last step, and Shift-Command-Z redoes it.",
            "Command-1 to Command-8 show the pages in the View menu's order: Event, Results, Adults, Youth, Pre-Registered, Adult History CSV, Rooms, and Approved Proposals. They also bring the scheduler window back if it was closed.",
            "Command-F puts the cursor in the toolbar's search field.",
            "Command-L shows who introduces the selected youth, then their leader and parents (Board › Locate Leader and Parents).",
            "Command-B puts the adults selected on the Adults page on the board being drawn up (Adult › Add to Board).",
            "Command-N signs in an adult by hand (Adult › Add Adult…), and Shift-Command-N adds a room (Room › Add Room…).",
            "Command-O opens another event, and Command-I imports the sign-ups from SignUpGenius.",
            "Command-E saves the board results as a spreadsheet, and Shift-Command-E the page's list.",
            "Control-Command-I shows or hides the inspector.",
            "Command-Comma opens Settings, and Command-? opens this help.",
        ]),
        HelpSection("Keyboard shortcuts on the Event page", [
            "Return on a youth in the list takes their next step, as a double-click does.",
            "Return in the search opens the first room found, or the youth found.",
            "Tab to the room cards, and the arrow keys move from room to room. Return takes the selected room's next step, and Room › Rename… renames it.",
            "Return in the inspector's Find an adult puts the first adult found on the board.",
            "Board › Chair hands the chair to another member of the board being drawn up, and Board › Unlink Introducer unlinks the adult introducing the youth.",
        ]),
        HelpSection("Keyboard shortcuts on a table page", [
            "Return in the search goes to the first row found.",
            "Return on a row does what a double-click does: on Results, Youth, and Rooms it shows the row on the Event page, and on Adults it puts the selected adults on the board being drawn up. On the Adult History CSV page, Adult › Sign In for Today signs in the adults selected.",
            "In a cell, Return saves the change, and Escape puts the value back.",
            "On the Youth, Pre-Registered, and Adults pages, Delete deletes the selected row, asking first. On the Rooms page it removes the selected room if it is free.",
            "View › Sort By sorts the page by a column, either way.",
        ]),
        HelpSection("Keyboard shortcuts in a sheet", [
            "Return presses the highlighted button, and Escape cancels.",
            "In Change Members…, Return in Find an adult puts the first adult found on the board instead of saving.",
            "In Add an Adult, Return in Signed in before? fills the form in from the only match, or goes to the matches. Up and Down move through them, Up from the first goes back to the search, and Return or Space fills the form in from the one chosen.",
        ]),
        HelpSection("The data", [
            "Everything is saved the moment it changes, in the data folder you chose. Each event has its own dated folder; the adult history is kept across events.",
            "A data folder with no adult history gets a new, empty one, and Eagle Boards says where it put it. If you meant another folder, File › Choose Data Folder… switches to it.",
            "The files are the same ones the Java Eagle Board Scheduler used, so either program can open the folder.",
            "They hold personal information, some of it about minors. Keep the folder private and do not email the files around.",
            "Only the sign-in pages are on the network. The scheduler, the records and the settings are on this Mac alone.",
        ]),
        HelpSection("Donating", [
            "Eagle Boards is free. If it helps your board events, Help › Donate… lists ways to support its development, with a Venmo QR code a phone can scan.",
        ]),
    ]
}

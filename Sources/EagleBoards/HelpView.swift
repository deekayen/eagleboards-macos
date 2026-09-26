import SwiftUI

/// The operator's guide, kept short enough to read on the night.
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Running an Eagle Boards event").font(.largeTitle.bold())

                section("Before anyone arrives") {
                    step("Open Eagle Boards on the admin Mac. It opens today's event and starts the sign-in station.")
                    step("Click the sign-in status at the top left of the window. Scan the QR code with the tablet at the door, or type the address into its browser. The tablet must be on the same Wi-Fi as the Mac.")
                    step("For a second display or a projector by the door, choose Window › Sign-In Code (Command-3) and make it as large as you like.")
                    step("Add today's rooms with Add Room at the bottom of the sidebar, or Room › Add Room…, marking each Final or Project by what it is used for today. After the first event, Room › Copy Rooms From brings back last month's rooms.")
                    step("To hold two proposal reviews in one room, add it twice, e.g. 200A and 200B.")
                    step("To rename a room, right-click it in the sidebar or on its card and choose Rename…. A board already in it moves with it; nobody is reseated.")
                    step("If macOS asks whether Eagle Boards may accept incoming network connections, click Allow. Otherwise the tablet cannot reach it.")
                }

                section("People sign in") {
                    step("At the tablet, a youth taps I am a Youth and an adult taps I am 21+. Each fills in the form.")
                    step("People who pre-registered on SignUpGenius, and adults who have served before, are recognized by email and their form fills itself in.")
                    step("They appear in the scheduler the moment they register. Youth are numbered P1, P2… if they pre-registered and W1, W2… if they walked in, and the list keeps pre-registered youth ahead of walk-ins.")
                    step("Check the paperwork as youth sign in. If it is not in order, select them and choose Board › Postpone. Edit › Undo brings them back.")
                }

                section("Seat a board") {
                    step("The sidebar lists the youth Waiting, On Boards and Finished, the Adults, and every room. The inspector on the right follows the selected youth; View › Show Inspector brings it back if it is hidden.")
                    step("Select a waiting youth. The inspector proposes a board: a chair, enough members, and a free room of the right kind. It never picks adults from the youth's own unit. It picks with the whole waiting line in mind: it keeps adults who can chair free for the boards still to come, and uses adults whose troop rules them out for youth still waiting. If there aren't enough adults to do that it still proposes the best board it can.")
                    step("Change who sits on the board in the inspector: click someone in the free adults listed below the board to add them (type in Find an adult to narrow the list), and − takes them off. In the Adults list you can also Command-click several adults and choose Adult › Add to Board (Command-B), or drag them onto the board. A board you have changed is kept while you look at other youth; Suggest a Board replaces it with a proposal.")
                    step("To choose every board yourself, set Settings › General › When you select a waiting youth to Start with an empty board. Selecting a youth then picks only a free room.")
                    step("Press Seat Board… in the inspector or the toolbar, press Command-Return, or double-click the youth. You can also drag a waiting youth onto a free room in the sidebar. The sheet lists anything that stops the board -- too few or too many members, no qualified chair, someone already on another board -- and anything worth a second look, each of which needs its own tick.")
                    step("Choose the chair. Only members whose role for this kind of board is Chair are offered. If none is free, promote someone in the Records window by changing their role.")
                    step("Seating gives the members the room and the paperwork. The youth waits outside.")
                }

                section("Start the review") {
                    step("When the members have finished reading, select the youth and press Start Review (Command-Return again). The confirmation lists who came to support the youth (they say so at sign-in) and where they are, even on another board, then the youth's leader and parents if they signed in, so they can be fetched too.")
                    step("At sign-in, adults can say \"No thanks\" to one kind of board (they are never seated on it), whether today counts toward a Wood Badge ticket item (marked with a small five-colored pentagon next to their name), and which youth they came with. Proposed boards favour those who came to serve on any board.")
                    step("If an adult came with a youth but did not say so at sign-in, select the youth and use Link an Adult under With Them in the inspector. Right-click them there to unlink.")
                }

                section("Complete") {
                    step("When the board has finished, press Complete… (Command-Return), choose the result and add any notes.")
                    step("The room and the members are freed for the next board. The inspector lists the youth's leader and parents so someone can find them.")
                }

                section("Board sizes") {
                    bullet("A final board of review has three to six members (Guide to Advancement 8.0.0.3). Three is the norm; four to six asks you to confirm; seven is refused.")
                    bullet("A project proposal review has two to six. Two is the norm.")
                    bullet("This council does not allow adults from the youth's own unit on the board. You may override that, but a board must still have at least one member from outside the unit (8.0.3.0).")
                }

                section("Room timers") {
                    bullet("The Dock icon shows how many youth are waiting. If a room passes its red time while you are in another app, a notification says so; macOS asks once whether to allow them, after the first board is seated.")
                    bullet("Each busy room shows the minutes since its last step. While a board convenes the card turns red after 30 minutes. Once the review starts, a final board turns yellow at 30 and red at 45; a proposal review at 25 and 40.")
                    bullet("They are prompts, not limits. Change them in Settings › Timers.")
                }

                section("Menus") {
                    bullet("Every action is in the Board, Adult and Room menus, and on the right-click menu of a youth, an adult or a room.")
                    bullet("Edit › Undo (Command-Z) takes back the last step: seating, starting, completing, postponing or resetting a board, disabling or enabling an adult, linking, and adding, removing, renaming or swapping rooms. It is refused if the room or a member has been given to another board since.")
                    bullet("Board › Locate Leader and Parents (Command-L) shows who came with the selected youth, and where they are, in the inspector.")
                    bullet("Board › Reset Board undoes seating: the youth waits again and the room and members are freed.")
                    bullet("Adult › Disable for Today takes adults out of the pool, for example when they have gone home. Enable for Today brings them back.")
                    bullet("Room › Move Board to Another Room… moves a board, or swaps two boards.")
                    bullet("View › Waiting, On Boards, Finished, Adults and Rooms (Option-Command-1 to 5) switch lists.")
                    bullet("File › Export Board Results saves the event as a spreadsheet.")
                }

                section("The data") {
                    bullet("Everything is saved the moment it changes, in the data folder you chose. Each event has its own dated folder; the adult history is kept across events.")
                    bullet("The files are the same ones the Java Eagle Board Scheduler used, so either program can open the folder.")
                    bullet("They hold personal information, some of it about minors. Keep the folder private and do not email the files around.")
                    bullet("Only the sign-in pages are on the network. The scheduler, the records and the settings are on this Mac alone.")
                }

                section("Donating") {
                    bullet("Eagle Boards is free. If it helps your board events, Help › Donate lists ways to support its development.")
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title2.bold())
            content()
        }
    }

    private func step(_ text: String) -> some View {
        bullet(text)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

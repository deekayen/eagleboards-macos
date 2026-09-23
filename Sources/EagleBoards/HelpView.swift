import SwiftUI

/// The operator's guide, kept short enough to read on the night.
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Running an Eagle Boards night").font(.largeTitle.bold())

                section("Before anyone arrives") {
                    step("Open Eagle Boards on the admin Mac. It opens tonight and starts the sign-in station.")
                    step("Click the sign-in status at the top left of the window. Scan the QR code with the tablet at the door, or type the address into its browser. The tablet must be on the same Wi-Fi as the Mac.")
                    step("Add tonight's rooms in the Rooms panel, marking each Final or Project by what it is used for tonight. After the first night you can copy last month's rooms instead.")
                    step("To hold two proposal reviews in one room, add it twice, e.g. 200A and 200B.")
                    step("To rename a room, select it and click Rename…, or right-click its card. A board already in it moves with it; nobody is reseated.")
                    step("If macOS asks whether Eagle Boards may accept incoming network connections, click Allow. Otherwise the tablet cannot reach it.")
                }

                section("People sign in") {
                    step("At the tablet, a youth taps I am a Youth and an adult taps I am 21+. Each fills in the form.")
                    step("People who pre-registered on SignUpGenius, and adults who have served before, are recognized by email and their form fills itself in.")
                    step("They appear in the scheduler the moment they register. Youth are numbered P1, P2… if they pre-registered and W1, W2… if they walked in, and the list keeps pre-registered youth ahead of walk-ins.")
                    step("Check the paperwork as youth sign in. If it is not in order, select them and press Postpone.")
                }

                section("Seat a board") {
                    step("Select a youth. The scheduler proposes a board: a chair, enough members, and a free room of the right kind. It never picks adults from the youth's own unit.")
                    step("Change who sits on the board with the checkboxes in Adult Board Members. Checked adults stay checked while you click around; Clear empties the list.")
                    step("Press Seat Board. The sheet lists anything that stops the board -- too few or too many members, no qualified chair, someone already on another board -- and anything worth a second look, each of which needs its own tick.")
                    step("Choose the chair. Only members whose role for this kind of board is Chair are offered. If none is free, promote someone in the Records window by changing their role.")
                    step("Seating gives the members the room and the paperwork. The youth waits outside.")
                }

                section("Start the review") {
                    step("When the members have finished reading, select the youth and press Start Review. The confirmation lists the youth's leader and parents if they signed in, so they can be fetched too.")
                }

                section("Complete") {
                    step("When the board has finished, press Complete, choose the result and add any notes.")
                    step("The room and the members are freed for the next board, and the youth's leader and parents are listed so someone can find them.")
                }

                section("Board sizes") {
                    bullet("A final board of review has three to six members (Guide to Advancement 8.0.0.3). Three is the norm; four to six asks you to confirm; seven is refused.")
                    bullet("A project proposal review has two to six. Two is the norm.")
                    bullet("This council does not allow adults from the youth's own unit on the board. You may override that, but a board must still have at least one member from outside the unit (8.0.3.0).")
                }

                section("Room timers") {
                    bullet("Each busy room shows the minutes since its last step. While a board convenes the card turns red after 30 minutes. Once the review starts, a final board turns yellow at 30 and red at 45; a proposal review at 25 and 40.")
                    bullet("They are prompts, not limits. Change them in Settings › Timers.")
                }

                section("Other buttons") {
                    bullet("Locate finds the selected youth's leader and parents among the adults who signed in.")
                    bullet("Reset undoes seating: the youth waits again and the room and members are freed.")
                    bullet("Disable takes an adult out of the pool for tonight, for example when they have gone home. Enable brings them back.")
                    bullet("Swap moves a board to another room, or swaps two boards.")
                    bullet("File › Export Board Results saves the night as a spreadsheet.")
                }

                section("The data") {
                    bullet("Everything is saved the moment it changes, in the data folder you chose. Each night has its own dated folder; the adult history is kept across nights.")
                    bullet("The files are the same ones the Java Eagle Board Scheduler used, so either program can open the folder.")
                    bullet("They hold personal information, some of it about minors. Keep the folder private and do not email the files around.")
                    bullet("Only the sign-in pages are on the network. The scheduler, the records and the settings are on this Mac alone.")
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

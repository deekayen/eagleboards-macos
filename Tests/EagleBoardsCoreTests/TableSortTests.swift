import EagleBoardsCore
import Testing

/// View › Sort By sorts a table page as a click on a column heading does.
@Suite("Sorting a table from the menu")
struct TableSortTests {
    @Test func choosingTheColumnAlreadySortedByKeepsItsOrder() {
        let newestFirst = TableSort("lastEvent", ascending: false)
        #expect(newestFirst.sorting(by: "lastEvent") == newestFirst)
        #expect(newestFirst.sorting(by: "lastEvent", ascendingFirst: true) == newestFirst)
    }

    @Test func anotherColumnStartsAscending() {
        let byLast = TableSort("Last Name", ascending: false)
        #expect(byLast.sorting(by: "First Name") == TableSort("First Name", ascending: true))
    }

    @Test func aColumnThatListsTheNewestFirstStartsDescending() {
        #expect(TableSort("last").sorting(by: "lastEvent", ascendingFirst: false) == TableSort("lastEvent", ascending: false))
    }
}

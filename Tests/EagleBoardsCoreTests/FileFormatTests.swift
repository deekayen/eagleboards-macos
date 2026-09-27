import EagleBoardsCore
import Foundation
import Testing

/// The data files must stay readable by the Java Eagle Board Scheduler and
/// vice versa, so a district can move between the two -- or fall back to the
/// Java app on the night -- without converting anything.
@Suite("Data files")
struct FileFormatTests {
    /// The exact header lines the Java app writes.
    @Test func headersMatchTheJavaApp() {
        #expect(CSVFile.render([Scout]()) == "Type,ID,RegNum,Last,First,Email,Phone,UnitType,Unit,UnitName,DOB,BoardType,Leader,RegTime,LastUpdateTime,Flags,Room,Status,Result,BoardChair,BoardChairID,BoardMembers,BoardMembersIDs,Notes\n")
        #expect(CSVFile.render([Adult]()) == "Type,ID,Last,First,Email,Phone,UnitType,Unit,UnitName,ProjectReview,FinalBoard,RegTime,Room,Flags,Sel,BoardHistory,WoodBadge,Supporting\n")
        #expect(CSVFile.render([Room]()) == "Type,ID,Room,BoardType,Scout,Leaders,RegTime\n")
    }

    /// Adults files written before WoodBadge and Supporting were appended.
    @Test func anOlderAdultsFileWithoutTonightsAnswersStillReads() throws {
        let older = """
            Type,ID,Last,First,Email,Phone,UnitType,Unit,UnitName,ProjectReview,FinalBoard,RegTime,Room,Flags,Sel,BoardHistory
            ADULT,ADULT:Able:Ann:2001,Able,Ann,,,Troop,2001,Troop2001,Member,Chair,,101,P,,(2026-08-25)

            """
        let adult = try #require(CSVFile.parse(Adult.self, text: older).first)
        #expect(adult.room == "101")
        #expect(adult.woodBadge.isEmpty && adult.supporting.isEmpty)
        #expect(adult.cameForAnyBoard)
    }

    @Test func aJavaWrittenRowReadsBackUnchanged() {
        let javaFile = """
            Type,ID,RegNum,Last,First,Email,Phone,UnitType,Unit,UnitName,DOB,BoardType,Leader,RegTime,LastUpdateTime,Flags,Room,Status,Result,BoardChair,BoardChairID,BoardMembers,BoardMembersIDs,Notes
            SCOUT,SCOUT:Doe:Jan:1776,P1,Doe,Jan,jan@example.org,770-555-0100,Troop,1776,Troop1776,1/2/2009,Final,Lee Leader,2026-09-22_18:31-0400,2026-09-22_19:02-0400,,101,InProgress,,Chris Chair,ADULT:Chair:Chris:12,Chris Chair~Morgan Member,ADULT:Chair:Chris:12~ADULT:Member:Morgan:34,Nervous~ but ready

            """
        let youth = CSVFile.parse(Scout.self, text: javaFile)
        #expect(youth.count == 1)
        #expect(youth[0].id == "SCOUT:Doe:Jan:1776")
        #expect(youth[0].status == .inProgress)
        #expect(youth[0].boardType == .finalBoard)
        #expect(youth[0].room == "101")
        #expect(youth[0].notes == "Nervous~ but ready")
        #expect(CSVFile.render(youth) == javaFile)
    }

    @Test func commasAndLineBreaksCannotBreakARow() {
        var youth = Scout.blank(at: Date())
        youth.first = "Jan"
        youth.last = "Doe"
        youth.notes = "Strong answers, good eye contact\nAdjourn? No."
        let rendered = CSVFile.render([youth])
        #expect(rendered.split(separator: "\n").count == 2)
        #expect(rendered.contains("Strong answers~ good eye contact+Adjourn? No."))
    }

    @Test func windowsLineEndingsBlankLinesAndUnknownColumnsAreTolerated() {
        let text = "Type,ID,Room,BoardType,Mystery,Scout\r\nROOM,ROOM:101,101,Final,xyz,\r\n\r\nROOM,ROOM:200A,200A,Project,,Someone\r\n"
        let rooms = CSVFile.parse(Room.self, text: text)
        #expect(rooms.map(\.name) == ["101", "200A"])
        #expect(rooms[0].fields["Mystery"] == nil)
        #expect(rooms[1].scoutName == "Someone")
    }

    @Test func aPersonWithNoIDGetsTheJavaStyleOne() {
        let text = "Type,ID,Last,First,Unit,UnitType\nADULT,,Smith,Pat,42,Crew\n"
        let adults = CSVFile.parse(Adult.self, text: text)
        #expect(adults[0].id == "ADULT:Smith:Pat:42")
        #expect(adults[0].unitName == "Crew42")
    }

    @Test func aJavaConfigFileReads() {
        let text = """
            # Eagle Board Scheduler configuration
            # Edit the values after each '='. Lines starting with # are comments.

            Type=CONFIG
            ID=DEFAULT
            RefreshTimeSecs = 15
            FinalRedMins:50
            RegisteredColor=#ff0000
            ProjectYellowMins=
            """
        let config = Config(fields: PropertiesFile.parse(text))
        #expect(config.refreshSeconds == 15)
        #expect(config.finalRedMinutes == 50)
        #expect(config.projectYellowMinutes == 25, "a blank value keeps the default")
        #expect(config.conveneRedMinutes == 30, "a missing value keeps the default")
        #expect(!PropertiesFile.render(config).contains("Color"),
                "a retired status color loads but is not written back (SPEC.md D-19)")
    }

    @Test func configRoundTrips() {
        var config = Config.standard
        config.finalYellowMinutes = 35
        let reread = Config(fields: PropertiesFile.parse(PropertiesFile.render(config)))
        #expect(reread == config)
        #expect(PropertiesFile.render(config).contains("FinalYellowMins=35\n"))
        #expect(!Config.columns.contains { $0.hasSuffix("Color") }, "status colors are not settings (SPEC.md D-19)")
    }

    @MainActor
    @Test func aNewFolderGetsEveryFile() throws {
        let scratch = try ScratchFolder()
        _ = try EventNight(folder: scratch.dataFolder, night: "2026-09-22")
        for file in ["config.properties", "Master_AdultHistory.csv", "2026-09-22/scouts.csv", "2026-09-22/adults.csv",
                     "2026-09-22/rooms.csv", "2026-09-22/scouts_scheduled.csv"] {
            #expect(FileManager.default.fileExists(atPath: scratch.url.appending(path: file).path), "\(file) exists")
        }
        #expect(scratch.dataFolder.nights() == ["2026-09-22"])
    }
}

@Suite("Timestamps")
struct TimestampTests {
    @Test func recordStampsRoundTripInAnyZone() throws {
        let moment = Date(timeIntervalSince1970: 1_790_118_300)
        for zoneName in ["America/New_York", "UTC", "Asia/Kolkata"] {
            let zone = try #require(TimeZone(identifier: zoneName))
            let stamp = Timestamp.recordStamp(for: moment, timeZone: zone)
            #expect(stamp.count == 21)
            #expect(Timestamp.date(fromRecordStamp: stamp) == moment)
        }
    }

    @Test func theJavaShapeParses() throws {
        let parsed = try #require(Timestamp.date(fromRecordStamp: "2026-09-22_19:05-0400"))
        #expect(parsed == Date(timeIntervalSince1970: 1_790_118_300))
        #expect(Timestamp.hourMinute(ofRecordStamp: "2026-09-22_19:05-0400") == "19:05")
    }

    @Test func minutesSinceIsWholeMinutes() {
        let later = Date(timeIntervalSince1970: 1_790_118_300 + 30 * 60 + 59)
        #expect(Timestamp.minutesSince(recordStamp: "2026-09-22_19:05-0400", now: later) == 30)
        #expect(Timestamp.minutesSince(recordStamp: "", now: later) == nil)
        #expect(Timestamp.minutesSince(recordStamp: "yesterday", now: later) == nil)
    }

    @Test func dayStampsNameNightFolders() {
        #expect(Timestamp.isDayStamp("2026-09-22"))
        #expect(!Timestamp.isDayStamp("2026-9-22"))
        #expect(!Timestamp.isDayStamp("notes-2026"))
        #expect(Timestamp.monthStamp(for: Date(timeIntervalSince1970: 1_790_118_300), timeZone: TimeZone(identifier: "UTC")!) == "2026-09")
    }
}

@Suite("Reports")
struct ReportTests {
    @Test func theBoardResultsReportHasTheJavaColumns() {
        var youth = Scout.blank(at: Date())
        youth.first = "Jan"
        youth.last = "Doe"
        youth.result = "Approved"
        youth.notes = "Calm, prepared"
        // On file from before D-7 and D-8; neither is exported.
        youth.dateOfBirth = "1/2/2010"
        youth.phone = "770-555-0100"
        let report = Reports.csv([youth], columns: Reports.boardResultColumns)
        let lines = report.split(separator: "\n")
        #expect(lines[0] == "RegNum,Last,First,Email,BoardType,UnitType,Unit,Leader,Status,Result,BoardChair,BoardMembers,Notes")
        #expect(lines[1] == ",Doe,Jan,,,,,,,Approved,,,Calm~ prepared")
    }

    /// The Records window's youth lists keep the data files' columns, with a
    /// birthdate or phone number on file left blank (SPEC.md D-7, D-8).
    @Test func anExportedYouthListWithholdsTheBirthdateAndPhone() {
        var youth = Scout.blank(at: Date())
        youth.first = "Jan"
        youth.last = "Doe"
        youth.email = "jan@example.org"
        youth.dateOfBirth = "1/2/2010"
        youth.phone = "770-555-0100"
        let exported = CSVFile.render([youth.forExport])
        #expect(exported.hasPrefix(CSVFile.render([Scout]())), "the same header")
        #expect(exported.contains("jan@example.org"))
        #expect(!exported.contains("1/2/2010") && !exported.contains("770-555-0100"))
        #expect(youth.phone == "770-555-0100", "the record keeps it")
    }
}

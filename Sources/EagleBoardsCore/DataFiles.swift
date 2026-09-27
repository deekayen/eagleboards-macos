import Foundation

/// Reading and writing the data files in the dialect the Java Eagle Board
/// Scheduler used, so either program can open the other's folder.
///
/// The CSV dialect is deliberately simple and has no quoting: a header row of
/// column names, then one row per record split on every comma. On write, a
/// comma inside a value becomes `~` and a line break becomes `+`, because
/// there is no other way to keep them from breaking the row. Columns the
/// record type does not know are dropped on read; missing ones read as empty.
public enum CSVFile {
    public static func read<Record: EventRecord>(_ type: Record.Type, from url: URL) throws -> [Record] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return parse(type, text: try readText(at: url))
    }

    public static func parse<Record: EventRecord>(_ type: Record.Type, text: String) -> [Record] {
        let lines = text.split(whereSeparator: \.isNewline)
        guard let headerLine = lines.first else { return [] }
        let header = headerLine.split(separator: ",").map(String.init)
        let knownColumns = Set(Record.columns)

        return lines.dropFirst().compactMap { line -> Record? in
            guard !line.allSatisfy(\.isWhitespace) else { return nil }
            let values = line.split(separator: ",", omittingEmptySubsequences: false)
            var fields: [String: String] = [:]
            for (column, value) in zip(header, values) where knownColumns.contains(column) {
                fields[column] = String(value)
            }
            var record = Record(fields: fields)
            if record["Type"].isEmpty {
                record["Type"] = Record.recordType
            }
            record.normalizeAfterLoad()
            return record
        }
    }

    public static func render<Record: EventRecord>(_ records: [Record]) -> String {
        var text = Record.columns.joined(separator: ",") + "\n"
        for record in records {
            text += Record.columns.map { flatten(record[$0]) }.joined(separator: ",") + "\n"
        }
        return text
    }

    public static func write<Record: EventRecord>(_ records: [Record], to url: URL) throws {
        try Data(render(records).utf8).write(to: url, options: .atomic)
    }

    /// Keep a value on one line and in one column.
    static func flatten(_ value: String) -> String {
        value
            .replacingOccurrences(of: ",", with: "~")
            .replacingOccurrences(of: "\n", with: "+")
            .replacingOccurrences(of: "\r", with: "+")
    }

    /// Files written by the Java app on Windows may be in the Windows code page
    /// rather than UTF-8; accept either.
    static func readText(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(decoding: data, as: UTF8.self)
    }
}

/// `config.properties`: one `key=value` per line, `#` comments.
///
/// Reading follows `java.util.Properties` closely enough for the values this
/// file holds (numbers, hex colors). Writing matches the Java app: a short
/// header comment, then every column in order, values written verbatim.
/// Saving does not keep hand-written comments, as it never did.
public enum PropertiesFile {
    public static func read(from url: URL) throws -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else { return .standard }
        return Config(fields: parse(try CSVFile.readText(at: url)))
    }

    public static func parse(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        var pendingLine = ""

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let leadingTrimmed = String(rawLine.drop(while: \.isWhitespace))
            var line: String
            if pendingLine.isEmpty {
                if leadingTrimmed.isEmpty || leadingTrimmed.hasPrefix("#") || leadingTrimmed.hasPrefix("!") {
                    continue
                }
                line = leadingTrimmed
            } else {
                line = pendingLine + leadingTrimmed
                pendingLine = ""
            }
            // A line ending in an odd number of backslashes continues onto the next.
            let trailingBackslashes = line.reversed().prefix(while: { $0 == "\\" }).count
            if trailingBackslashes % 2 == 1 {
                line.removeLast()
                pendingLine = line
                continue
            }
            let (key, value) = splitKeyValue(line)
            values[unescape(key)] = unescape(value)
        }
        if !pendingLine.isEmpty {
            let (key, value) = splitKeyValue(pendingLine)
            values[unescape(key)] = unescape(value)
        }
        return values
    }

    public static func render(_ config: Config) -> String {
        var text = "# Eagle Board Scheduler configuration\n"
        text += "# Edit the values after each '='. Lines starting with # are comments.\n\n"
        for column in Config.columns {
            text += "\(column)=\(config[column])\n"
        }
        return text
    }

    public static func write(_ config: Config, to url: URL) throws {
        try Data(render(config).utf8).write(to: url, options: .atomic)
    }

    /// Key ends at the first unescaped `=`, `:` or whitespace; the separator
    /// and the whitespace around it are not part of the value.
    private static func splitKeyValue(_ line: String) -> (String, String) {
        var key = ""
        var index = line.startIndex
        var escaped = false
        while index < line.endIndex {
            let character = line[index]
            if escaped {
                key.append("\\")
                key.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "=" || character == ":" || character.isWhitespace {
                break
            } else {
                key.append(character)
            }
            index = line.index(after: index)
        }
        var rest = line[index...].drop(while: { $0 == " " || $0 == "\t" })
        if let separator = rest.first, separator == "=" || separator == ":" {
            rest = rest.dropFirst().drop(while: { $0 == " " || $0 == "\t" })
        }
        return (key, String(rest))
    }

    private static func unescape(_ text: String) -> String {
        guard text.contains("\\") else { return text }
        var output = ""
        var characters = text.makeIterator()
        while let character = characters.next() {
            guard character == "\\", let escaped = characters.next() else {
                output.append(character)
                continue
            }
            switch escaped {
            case "t": output.append("\t")
            case "n": output.append("\n")
            case "r": output.append("\r")
            case "f": output.append("\u{0C}")
            case "u":
                var hexDigits = ""
                for _ in 0..<4 {
                    if let digit = characters.next() { hexDigits.append(digit) }
                }
                if let code = UInt32(hexDigits, radix: 16), let scalar = Unicode.Scalar(code) {
                    output.append(Character(scalar))
                }
            default: output.append(escaped)
            }
        }
        return output
    }
}

/// Exports for people to open in a spreadsheet.
public enum Reports {
    /// The board results report: the Java app's `Report.csv` columns.
    public static let boardResultColumns = [
        "RegNum", "Last", "First", "Phone", "Email", "BoardType", "UnitType", "Unit",
        "Leader", "Status", "Result", "BoardChair", "BoardMembers", "Notes",
    ]

    /// The chosen columns of `records`, in the data files' comma dialect.
    public static func csv<Record: EventRecord>(_ records: [Record], columns: [String]) -> String {
        var text = columns.joined(separator: ",") + "\n"
        for record in records {
            text += columns.map { CSVFile.flatten(record[$0]) }.joined(separator: ",") + "\n"
        }
        return text
    }
}

import Foundation

enum FinderPasteFileNamer {
    static func destinationURL(
        directory: URL,
        date: Date,
        number: Int,
        fileExtension: String?,
        calendar: Calendar,
        fileExists: (URL) -> Bool
    ) -> URL {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let dateText = String(
            format: "%04d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        let base = "\(dateText)-\(String(format: "%03d", max(number, 1)))"

        let baseURL = candidateURL(directory: directory, stem: base, fileExtension: fileExtension)
        guard fileExists(baseURL) else { return baseURL }

        let seconds = Int64(date.timeIntervalSince1970.rounded(.down))
        let secondsURL = candidateURL(
            directory: directory,
            stem: "\(base)-\(seconds)",
            fileExtension: fileExtension
        )
        guard fileExists(secondsURL) else { return secondsURL }

        let milliseconds = Int64((date.timeIntervalSince1970 * 1_000).rounded(.down))
        let millisecondStem = "\(base)-\(milliseconds)"
        let millisecondsURL = candidateURL(
            directory: directory,
            stem: millisecondStem,
            fileExtension: fileExtension
        )
        guard fileExists(millisecondsURL) else { return millisecondsURL }

        var suffix = 1
        while true {
            let url = candidateURL(
                directory: directory,
                stem: "\(millisecondStem)-\(suffix)",
                fileExtension: fileExtension
            )
            if !fileExists(url) {
                return url
            }
            suffix += 1
        }
    }

    private static func candidateURL(
        directory: URL,
        stem: String,
        fileExtension: String?
    ) -> URL {
        let filename: String
        if let fileExtension, !fileExtension.isEmpty {
            filename = "\(stem).\(fileExtension)"
        } else {
            filename = stem
        }
        return directory.appendingPathComponent(filename, isDirectory: false)
    }
}

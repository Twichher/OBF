import Foundation

final class DocumentStore {
    let fileURL: URL

    init(fileURL: URL = URL(fileURLWithPath: "/Users/vladflorinskij/Documents/obf_project/onebigfile.md")) {
        self.fileURL = fileURL
    }

    func load() -> String {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: fileURL.path, contents: Data())
            return ""
        }
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    func save(markdown: String) {
        try? markdown.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

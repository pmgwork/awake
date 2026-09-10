import Foundation
import Combine

@MainActor
public final class DownloadMonitor: ObservableObject {
    public static let shared = DownloadMonitor()

    @Published public private(set) var isDownloading = false
    @Published public private(set) var activeDownloadCount = 0
    @Published public private(set) var activeFileNames: [String] = []

    nonisolated private static let partialSuffixes = [
        ".crdownload",
        ".download",
        ".part",
        ".partial",
        ".opdownload",
    ]

    private var folderURL: URL
    private var timer: Timer?
    private let queue = DispatchQueue(label: "pmgwork.awake.download-monitor", qos: .utility)
    private var reloadInProgress = false

    public init(folderURL: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!) {
        self.folderURL = folderURL
        startMonitoring()
    }

    deinit { timer?.invalidate() }

    public func updateFolder(path: String) {
        let expandedPath = NSString(string: path).expandingTildeInPath
        folderURL = URL(fileURLWithPath: expandedPath, isDirectory: true)
        reloadNow()
    }

    public func reloadNow() {
        guard !reloadInProgress else { return }
        reloadInProgress = true
        let folderURL = self.folderURL
        queue.async { [weak self] in
            let names = Self.partialDownloadNames(in: folderURL)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.activeFileNames = names
                self.activeDownloadCount = names.count
                self.isDownloading = !names.isEmpty
                self.reloadInProgress = false
            }
        }
    }

    nonisolated public static func partialDownloadNames(
        in folderURL: URL,
        fileManager: FileManager = .default
    ) -> [String] {
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.nameKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var names: [String] = []
        for case let url as URL in enumerator {
            let lowercasedName = url.lastPathComponent.lowercased()
            if partialSuffixes.contains(where: lowercasedName.hasSuffix) {
                names.append(url.lastPathComponent)
                if lowercasedName.hasSuffix(".download") {
                    enumerator.skipDescendants()
                }
            }
        }
        return names.sorted()
    }

    private func startMonitoring() {
        reloadNow()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reloadNow() }
        }
    }
}

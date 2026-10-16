import Foundation
import Combine

@MainActor
public final class DownloadMonitor: ObservableObject {
    public static let shared = DownloadMonitor(startsAutomatically: false)

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
    private var observer: FileTreeObserver?
    private var generation = 0
    private var reloadPending = false
    private var isMonitoring = false

    public init(
        folderURL: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!,
        startsAutomatically: Bool = true
    ) {
        self.folderURL = folderURL
        if startsAutomatically { startMonitoring() }
    }

    deinit { timer?.invalidate() }

    public func updateFolder(path: String) {
        let expandedPath = NSString(string: path).expandingTildeInPath
        folderURL = URL(fileURLWithPath: expandedPath, isDirectory: true)
        generation += 1
        if isMonitoring {
            installObserver()
            reloadNow()
        }
    }

    public func reloadNow() {
        guard !reloadInProgress else {
            reloadPending = true
            return
        }
        reloadInProgress = true
        reloadPending = false
        let generation = self.generation
        let folderURL = self.folderURL
        queue.async { [weak self] in
            let names = Self.partialDownloadNames(in: folderURL)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reloadInProgress = false
                if self.generation == generation {
                    if self.activeFileNames != names { self.activeFileNames = names }
                    if self.activeDownloadCount != names.count { self.activeDownloadCount = names.count }
                    if self.isDownloading != !names.isEmpty { self.isDownloading = !names.isEmpty }
                }
                if self.isMonitoring && (self.reloadPending || self.generation != generation) {
                    self.reloadNow()
                }
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

    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        installObserver()
        reloadNow()
        // Recover missed notifications, replaced folders, or unavailable streams.
        // Normal changes trigger a scan through FSEvents instead of polling trees.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reloadNow() }
        }
    }

    public func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        observer = nil
        generation += 1
        reloadPending = false
        if !activeFileNames.isEmpty { activeFileNames = [] }
        if activeDownloadCount != 0 { activeDownloadCount = 0 }
        if isDownloading { isDownloading = false }
    }

    private func installObserver() {
        observer = nil
        observer = FileTreeObserver(url: folderURL) { [weak self] in
            self?.reloadNow()
        }
    }
}

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

    /// Partial files inside subfolders count only while they are being
    /// written. Extracted archives and projects can contain stale files with
    /// these suffixes that would otherwise keep the Mac awake indefinitely.
    nonisolated public static let nestedPartialFileMaxAge: TimeInterval = 10 * 60

    nonisolated public static func partialDownloadNames(
        in folderURL: URL,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> [String] {
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.nameKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var names: [String] = []
        for case let url as URL in enumerator {
            let lowercasedName = url.lastPathComponent.lowercased()
            guard partialSuffixes.contains(where: lowercasedName.hasSuffix) else { continue }
            let isBundle = lowercasedName.hasSuffix(".download")
            if isBundle {
                enumerator.skipDescendants()
            }
            if enumerator.level > 1 && !isRecentlyModified(url, isBundle: isBundle, fileManager: fileManager, now: now) {
                continue
            }
            names.append(url.lastPathComponent)
        }
        return names.sorted()
    }

    nonisolated private static func isRecentlyModified(
        _ url: URL,
        isBundle: Bool,
        fileManager: FileManager,
        now: Date
    ) -> Bool {
        func modificationDate(_ url: URL) -> Date? {
            try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        var dates = [modificationDate(url)].compactMap { $0 }
        // Safari writes into a file inside the .download bundle, which does
        // not update the bundle's own date.
        if isBundle, let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) {
            dates += contents.compactMap(modificationDate)
        }
        guard let newest = dates.max() else { return false }
        return now.timeIntervalSince(newest) < nestedPartialFileMaxAge
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

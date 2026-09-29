//
//  LinkMoverViewModel.swift
//  LinkMover
//
//  Created by Codex on 2026/6/5.
//

import AppKit
import Combine
import Foundation
import SwiftUI

struct DirectorySnapshot {
    let exists: Bool
    let isDirectory: Bool
    let isSymlink: Bool
    let sizeInBytes: Int64?
    let availableSpace: Int64?
    let isWritable: Bool
}

enum OverallCheckState {
    case awaitingInput
    case pass
    case warning
    case fail
}

struct CheckResult: Identifiable {
    enum State {
        case pass
        case warning
        case fail
        case pending
    }

    let id = UUID()
    let title: String
    let message: String
    let state: State

    var symbolName: String {
        switch state {
        case .pass: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .fail: "xmark.circle.fill"
        case .pending: "circle.dotted"
        }
    }

    var color: Color {
        switch state {
        case .pass: .green
        case .warning: .orange
        case .fail: .red
        case .pending: .secondary
        }
    }
}

struct LogEntry: Identifiable {
    enum Level: Sendable {
        case info
        case success
        case error
    }

    let id = UUID()
    let date: Date
    let level: Level
    let message: String

    var displayText: String {
        "[\(Self.formatter.string(from: date))] \(message)"
    }

    var color: Color {
        switch level {
        case .info: .primary
        case .success: .green
        case .error: .red
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

struct PathPreset: Identifiable {
    let id = UUID()
    let title: String
    let path: String
}

@MainActor
final class LinkMoverViewModel: ObservableObject {
    @Published var sourceURL: URL?
    @Published var sourcePathText = ""
    @Published var targetParentURL: URL?
    @Published var targetParentPathText = ""
    @Published var destinationName = ""
    @Published var prefersAdminPrivileges = true
    @Published var sourceDetails: [String] = []
    @Published var targetDetails: [String] = []
    @Published var checkResults: [CheckResult] = []
    @Published var logs: [LogEntry] = []
    @Published var isBusy = false
    @Published var successSummary: String?
    @Published var activityMessage: String?
    @Published var sourceSnapshot: DirectorySnapshot?
    @Published var targetSnapshot: DirectorySnapshot?

    private var localization: LocalizationManager
    private let fileManager = FileManager.default
    private let protectedPaths = ["/", "/System", "/System/Library", "/bin", "/sbin", "/usr/bin", "/usr/sbin", "/etc", "/private/etc"]
    private var rollbackPair: (source: URL, target: URL)?
    private var cancellables = Set<AnyCancellable>()

    init(localization: LocalizationManager) {
        self.localization = localization
        self.sourceDetails = [localization.strings.notSelectedDirectory]
        self.targetDetails = [localization.strings.notSelectedDirectory]
        localization.$language
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.objectWillChange.send()
                    await self.refreshAll()
                }
            }
            .store(in: &cancellables)
    }

    private var strings: Strings {
        localization.strings
    }

    var sourcePathDisplay: String {
        sourceURL?.path(percentEncoded: false) ?? strings.notSelectedSourceDirectory
    }

    var targetParentPathDisplay: String {
        targetParentURL?.path(percentEncoded: false) ?? strings.notSelectedTargetParentDirectory
    }

    var destinationURL: URL? {
        guard let targetParentURL, !destinationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return targetParentURL.appendingPathComponent(destinationName, isDirectory: true)
    }

    var destinationPathDisplay: String {
        destinationURL?.path(percentEncoded: false) ?? strings.destinationPathPlaceholder
    }

    var previewCommand: String {
        guard let sourceURL, let targetParentURL, let destinationURL else {
            return strings.localized(
                zh: "mv \"原目录\" \"目标父目录/\" && ln -s \"目标完整路径\" \"原路径\"",
                en: "mv \"source folder\" \"target parent/\" && ln -s \"full target path\" \"original path\""
            )
        }

        return """
        mv "\(sourceURL.path(percentEncoded: false))" "\(targetParentURL.path(percentEncoded: false))/"
        ln -s "\(destinationURL.path(percentEncoded: false))" "\(sourceURL.path(percentEncoded: false))"
        """
    }

    var canMigrate: Bool {
        !isBusy && !checkResults.contains(where: { $0.state == .fail }) && sourceURL != nil && destinationURL != nil
    }

    var canRollback: Bool {
        rollbackPair != nil
    }

    var activeTargetURL: URL? {
        rollbackPair?.target ?? destinationURL
    }

    var requiresAdminPrivileges: Bool {
        guard let sourceURL, let targetParentURL else {
            return false
        }

        return !isWritableDirectory(at: sourceURL.deletingLastPathComponent())
            || !isWritableDirectory(at: targetParentURL)
    }

    var willUseAdminPrivileges: Bool {
        prefersAdminPrivileges && requiresAdminPrivileges
    }

    var privilegeStatusMessage: String {
        if requiresAdminPrivileges {
            return prefersAdminPrivileges
                ? strings.localized(zh: "当前目录涉及受保护位置，执行时会弹出管理员认证。", en: "This location is protected. The app will prompt for administrator authentication during execution.")
                : strings.localized(zh: "当前目录需要管理员权限；关闭该选项后将无法开始迁移。", en: "This location requires administrator access. Migration cannot start while this option is off.")
        }

        return strings.localized(zh: "当前路径可直接操作，不会触发管理员认证。", en: "This path can be operated on directly and will not trigger administrator authentication.")
    }

    var confirmationMessage: String {
        var message = strings.localized(
            zh: "将把原目录移动到目标位置，并在原路径创建软链接。请确认没有应用正在使用该目录。",
            en: "The source folder will be moved to the target location, and a symbolic link will be created at the original path. Make sure no app is currently using this folder."
        )
        if willUseAdminPrivileges {
            message += strings.localized(zh: " 本次操作会请求管理员权限。", en: " This operation will request administrator access.")
        }
        return message
    }

    var failCount: Int {
        checkResults.filter { $0.state == .fail }.count
    }

    var warningCount: Int {
        checkResults.filter { $0.state == .warning }.count
    }

    var hasFailures: Bool {
        failCount > 0
    }

    var hasWarnings: Bool {
        warningCount > 0
    }

    var passCount: Int {
        checkResults.filter { $0.state == .pass }.count
    }

    var isConfigured: Bool {
        sourceURL != nil && targetParentURL != nil
    }

    var overallCheckState: OverallCheckState {
        guard isConfigured else {
            return .awaitingInput
        }
        if hasFailures {
            return .fail
        }
        if hasWarnings {
            return .warning
        }
        return .pass
    }

    var allChecksPassed: Bool {
        isConfigured && failCount == 0 && warningCount == 0
    }

    var isSameVolume: Bool? {
        guard let sourceURL, let targetParentURL else { return nil }
        return sourceURL.volumeIdentifierDescription == targetParentURL.volumeIdentifierDescription
    }

    var sourceSizeFormatted: String? {
        sourceSnapshot?.sizeInBytes.map { Self.byteFormatterString(from: $0, locale: strings.locale) }
    }

    var targetFreeSpaceFormatted: String? {
        targetSnapshot?.availableSpace.map { Self.byteFormatterString(from: $0, locale: strings.locale) }
    }

    var spaceUsageFraction: Double? {
        guard let needed = sourceSnapshot?.sizeInBytes,
              let free = targetSnapshot?.availableSpace,
              free > 0 else { return nil }
        return min(max(Double(needed) / Double(free), 0.0), 1.0)
    }

    var commonPresets: [PathPreset] {
        [
            PathPreset(title: "Xcode iOS DeviceSupport", path: "~/Library/Developer/Xcode/iOS DeviceSupport"),
            PathPreset(title: "Xcode watchOS DeviceSupport", path: "~/Library/Developer/Xcode/watchOS DeviceSupport"),
            PathPreset(title: "Xcode DerivedData", path: "~/Library/Developer/Xcode/DerivedData"),
            PathPreset(title: "Xcode Archives", path: "~/Library/Developer/Xcode/Archives"),
            PathPreset(title: "CocoaPods Cache", path: "~/Library/Caches/CocoaPods"),
            PathPreset(title: "Android AVD", path: "~/.android/avd")
        ]
    }

    static func sanitizePath(_ raw: String) -> String {
        var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if (path.hasPrefix("\"") && path.hasSuffix("\"")) || (path.hasPrefix("'") && path.hasSuffix("'")) {
            path = String(path.dropFirst().dropLast())
        }
        path = path.replacingOccurrences(of: "\\ ", with: " ")
        if path.hasPrefix("~") {
            path = (path as NSString).expandingTildeInPath
        }
        if path.count > 1 && path.hasSuffix("/") {
            path = String(path.dropLast())
        }
        return path
    }

    func updateSourcePath(from text: String) {
        let cleaned = Self.sanitizePath(text)
        sourcePathText = cleaned
        if cleaned.isEmpty {
            sourceURL = nil
            destinationName = ""
            Task { await refreshAll() }
            return
        }
        let url = URL(fileURLWithPath: cleaned).standardizedFileURL
        sourceURL = url
        destinationName = url.lastPathComponent
        Task { await refreshAll() }
    }

    func updateTargetParentPath(from text: String) {
        let cleaned = Self.sanitizePath(text)
        targetParentPathText = cleaned
        if cleaned.isEmpty {
            targetParentURL = nil
            Task { await refreshAll() }
            return
        }
        let url = URL(fileURLWithPath: cleaned).standardizedFileURL
        targetParentURL = url
        Task { await refreshAll() }
    }

    func pasteFromClipboard(forSource: Bool) {
        if let string = NSPasteboard.general.string(forType: .string) {
            if forSource {
                updateSourcePath(from: string)
            } else {
                updateTargetParentPath(from: string)
            }
        }
    }

    func clearPath(forSource: Bool) {
        if forSource {
            updateSourcePath(from: "")
        } else {
            updateTargetParentPath(from: "")
        }
    }

    func applyPreset(_ preset: PathPreset) {
        updateSourcePath(from: preset.path)
    }

    func clearLogs() {
        logs.removeAll()
    }

    func copyLogs() {
        let allText = logs.map(\.displayText).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(allText, forType: .string)
    }

    func selectSourceDirectory() {
        let initialDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer", isDirectory: true)
        guard let url = pickDirectory(
            title: strings.localized(zh: "选择要迁移的目录", en: "Choose the folder to migrate"),
            initialDirectory: initialDirectory
        ) else { return }
        let stdURL = url.standardizedFileURL
        sourceURL = stdURL
        sourcePathText = stdURL.path(percentEncoded: false)
        destinationName = stdURL.lastPathComponent
        Task {
            await refreshAll()
        }
    }

    func selectTargetParentDirectory() {
        guard let url = pickDirectory(
            title: strings.localized(zh: "选择目标父目录", en: "Choose the target parent folder"),
            initialDirectory: targetParentURL
        ) else { return }
        let stdURL = url.standardizedFileURL
        targetParentURL = stdURL
        targetParentPathText = stdURL.path(percentEncoded: false)
        Task {
            await refreshAll()
        }
    }

    func refreshAll() async {
        guard !isBusy else { return }
        successSummary = nil
        async let sourceTask = snapshot(for: sourceURL)
        async let targetTask = snapshot(for: targetParentURL)
        let (sourceSnapshot, targetSnapshot) = await (sourceTask, targetTask)

        self.sourceSnapshot = sourceSnapshot
        self.targetSnapshot = targetSnapshot
        sourceDetails = describeSource(snapshot: sourceSnapshot)
        targetDetails = describeTarget(snapshot: targetSnapshot)
        checkResults = buildChecks()
    }

    func performMigration() async {
        guard let sourceURL, let targetParentURL, let destinationURL else { return }
        isBusy = true
        successSummary = nil
        activityMessage = strings.localized(zh: "准备迁移...", en: "Preparing migration...")
        defer {
            isBusy = false
            activityMessage = nil
        }

        let usesAdmin = willUseAdminPrivileges
        let releasedBytes = sourceSnapshot?.sizeInBytes
        let updateProgress: @MainActor @Sendable (LogEntry.Level, String) -> Void = { [weak self] level, message in
            self?.activityMessage = message
            self?.appendLog(level, message)
        }
        let progress: @Sendable (LogEntry.Level, String) async -> Void = { level, message in
            await updateProgress(level, message)
        }

        do {
            let task = Task.detached(priority: .userInitiated) {
                try await Self.performMigrationSteps(
                    sourceURL: sourceURL,
                    targetParentURL: targetParentURL,
                    destinationURL: destinationURL,
                    useAdminPrivileges: usesAdmin,
                    progress: progress
                )
            }
            let needsRollback = try await task.value

            if needsRollback {
                rollbackPair = (source: sourceURL, target: destinationURL)
            } else {
                rollbackPair = nil
                successSummary = releasedBytes.map {
                    strings.localized(
                        zh: "已释放空间 \(Self.byteFormatterString(from: $0, locale: strings.locale))",
                        en: "Freed up \(Self.byteFormatterString(from: $0, locale: strings.locale))"
                    )
                } ?? strings.localized(zh: "迁移成功", en: "Migration completed")
            }
        } catch {
            appendLog(.error, strings.localized(zh: "迁移失败：\(error.localizedDescription)", en: "Migration failed: \(error.localizedDescription)"))
        }

        await refreshAll()
    }

    func rollbackMove() async {
        guard let rollbackPair else { return }
        isBusy = true
        activityMessage = strings.localized(zh: "正在恢复原位置...", en: "Restoring original location...")
        defer {
            isBusy = false
            activityMessage = nil
        }

        do {
            let usesAdmin = willUseAdminPrivileges || !isWritableDirectory(at: rollbackPair.source.deletingLastPathComponent())
            let task = Task.detached(priority: .userInitiated) {
                try Self.removeItemIfNeeded(at: rollbackPair.source, useAdminPrivileges: usesAdmin)
                try Self.moveItem(from: rollbackPair.target, to: rollbackPair.source, useAdminPrivileges: usesAdmin)
            }
            try await task.value
            self.rollbackPair = nil
            successSummary = nil
            appendLog(.success, strings.localized(zh: "已恢复到原路径：\(rollbackPair.source.path(percentEncoded: false))", en: "Restored to original path: \(rollbackPair.source.path(percentEncoded: false))"))
        } catch {
            appendLog(.error, strings.localized(zh: "恢复失败：\(error.localizedDescription)", en: "Restore failed: \(error.localizedDescription)"))
        }

        await refreshAll()
    }

    func retrySymlinkCreation() async {
        guard let rollbackPair else { return }
        isBusy = true
        activityMessage = strings.localized(zh: "正在重建软链接...", en: "Recreating symbolic link...")
        defer {
            isBusy = false
            activityMessage = nil
        }

        do {
            let usesAdmin = willUseAdminPrivileges
            let task = Task.detached(priority: .userInitiated) {
                try Self.createSymlink(at: rollbackPair.source, destination: rollbackPair.target, useAdminPrivileges: usesAdmin)
                try Self.validateMigration(source: rollbackPair.source, target: rollbackPair.target)
            }
            try await task.value
            self.rollbackPair = nil
            successSummary = strings.localized(zh: "软链接已补建", en: "Symbolic link recreated")
            appendLog(.success, strings.localized(zh: "软链接重建成功", en: "Symbolic link recreated successfully"))
        } catch {
            appendLog(.error, strings.localized(zh: "重新创建软链接失败：\(error.localizedDescription)", en: "Failed to recreate symbolic link: \(error.localizedDescription)"))
        }

        await refreshAll()
    }

    func openInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func pickDirectory(title: String, initialDirectory: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let initialDirectory {
            panel.directoryURL = initialDirectory
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func buildChecks() -> [CheckResult] {
        var results: [CheckResult] = []

        if sourceURL == nil {
            results.append(CheckResult(
                title: strings.sourceNotSelectedGuide,
                message: strings.sourceNotSelectedTip,
                state: .pending
            ))
        }

        if targetParentURL == nil {
            results.append(CheckResult(
                title: strings.targetNotSelectedGuide,
                message: strings.targetNotSelectedTip,
                state: .pending
            ))
        }

        guard let sourceURL, let targetParentURL else {
            return results
        }

        let sourcePath = sourceURL.path(percentEncoded: false)
        let targetPath = targetParentURL.path(percentEncoded: false)

        if protectedPaths.contains(where: { sourcePath == $0 || sourcePath.hasPrefix("\($0)/") && $0 != "/" }) {
            results.append(CheckResult(
                title: strings.localized(zh: "原目录位于关键系统路径", en: "Source Folder Is in a Critical System Path"),
                message: strings.localized(zh: "根目录和核心系统目录仍然禁止直接迁移。", en: "The root folder and core system directories cannot be migrated directly."),
                state: .fail
            ))
        } else {
            results.append(CheckResult(
                title: strings.localized(zh: "原目录路径可处理", en: "Source Path Can Be Processed"),
                message: strings.localized(zh: "未命中禁止迁移的核心系统目录。", en: "The source path is not inside a blocked core system directory."),
                state: .pass
            ))
        }

        if let sourceSnapshot {
            if sourceSnapshot.exists {
                results.append(CheckResult(title: strings.localized(zh: "原目录存在", en: "Source Folder Exists"), message: strings.localized(zh: "已找到待迁移目录。", en: "The folder to migrate was found."), state: .pass))
            } else {
                results.append(CheckResult(title: strings.localized(zh: "原目录不存在", en: "Source Folder Does Not Exist"), message: strings.localized(zh: "请选择一个真实存在的目录。", en: "Choose a folder that actually exists."), state: .fail))
            }

            if sourceSnapshot.isDirectory {
                results.append(CheckResult(title: strings.localized(zh: "原目录类型正确", en: "Source Folder Type Is Valid"), message: strings.localized(zh: "当前路径是普通目录。", en: "The current path is a normal directory."), state: .pass))
            } else {
                results.append(CheckResult(title: strings.localized(zh: "原目录不是普通目录", en: "Source Is Not a Normal Directory"), message: strings.localized(zh: "只支持迁移普通目录。", en: "Only normal directories are supported."), state: .fail))
            }

            if sourceSnapshot.isSymlink {
                results.append(CheckResult(title: strings.localized(zh: "原目录已是软链接", en: "Source Is Already a Symbolic Link"), message: strings.localized(zh: "不应再次迁移已链接的路径。", en: "A path that is already linked should not be migrated again."), state: .fail))
            } else {
                results.append(CheckResult(title: strings.localized(zh: "原目录不是软链接", en: "Source Is Not a Symbolic Link"), message: strings.localized(zh: "可以继续迁移。", en: "Migration can continue."), state: .pass))
            }
        }

        if let targetSnapshot {
            if targetSnapshot.exists {
                results.append(CheckResult(title: strings.localized(zh: "目标父目录存在", en: "Target Parent Folder Exists"), message: strings.localized(zh: "目标磁盘当前在线。", en: "The target disk is currently available."), state: .pass))
            } else {
                results.append(CheckResult(title: strings.localized(zh: "目标父目录不存在", en: "Target Parent Folder Does Not Exist"), message: strings.localized(zh: "目标磁盘离线或目录不存在。", en: "The target disk is offline or the folder does not exist."), state: .fail))
            }

            if targetSnapshot.isWritable || willUseAdminPrivileges {
                results.append(CheckResult(title: strings.localized(zh: "目标父目录可写", en: "Target Parent Folder Is Writable"), message: strings.localized(zh: "当前可以向目标位置写入数据。", en: "Data can be written to the target location."), state: .pass))
            } else {
                results.append(CheckResult(title: strings.localized(zh: "目标父目录不可写", en: "Target Parent Folder Is Not Writable"), message: strings.localized(zh: "请确认磁盘权限或只读挂载状态。", en: "Check disk permissions or whether it is mounted read-only."), state: .fail))
            }
        }

        if let destinationURL {
            if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
                results.append(CheckResult(title: strings.localized(zh: "目标路径已存在", en: "Destination Path Already Exists"), message: strings.localized(zh: "初版为了安全直接阻止该操作。", en: "This operation is blocked for safety in the current version."), state: .fail))
            } else {
                results.append(CheckResult(title: strings.localized(zh: "目标路径可用", en: "Destination Path Is Available"), message: strings.localized(zh: "目标完整路径尚未被占用。", en: "The full destination path is not occupied yet."), state: .pass))
            }

            if targetPath == sourcePath || destinationURL.standardizedFileURL == sourceURL.standardizedFileURL {
                results.append(CheckResult(title: strings.localized(zh: "目标路径非法", en: "Destination Path Is Invalid"), message: strings.localized(zh: "目标路径不能与原路径相同。", en: "The destination path cannot be the same as the source path."), state: .fail))
            }
        } else {
            results.append(CheckResult(title: strings.localized(zh: "缺少最终目录名", en: "Missing Final Folder Name"), message: strings.localized(zh: "请确认最终目录名。", en: "Confirm the final folder name."), state: .fail))
        }

        if let sourceBytes = sourceSnapshot?.sizeInBytes, let targetFreeBytes = targetSnapshot?.availableSpace {
            if targetFreeBytes >= sourceBytes {
                results.append(CheckResult(title: strings.localized(zh: "空间检查通过", en: "Space Check Passed"), message: strings.localized(zh: "目标磁盘剩余空间足够。", en: "The target disk has enough free space."), state: .pass))
            } else {
                results.append(CheckResult(
                    title: strings.localized(zh: "空间不足", en: "Not Enough Space"),
                    message: strings.localized(
                        zh: "需要 \(Self.byteFormatterString(from: sourceBytes, locale: strings.locale))，但可用空间不足。",
                        en: "Requires \(Self.byteFormatterString(from: sourceBytes, locale: strings.locale)), but the available free space is insufficient."
                    ),
                    state: .fail
                ))
            }
        }

        let sameVolume = sourceURL.volumeIdentifierDescription == targetParentURL.volumeIdentifierDescription
        let moveMessage = sameVolume
            ? strings.localized(zh: "同一卷内移动，通常更快。", en: "Moving within the same volume is usually faster.")
            : strings.localized(zh: "跨卷移动，将执行真实数据搬迁。", en: "Moving across volumes will perform a real data transfer.")
        results.append(CheckResult(
            title: sameVolume
                ? strings.localized(zh: "同磁盘移动", en: "Same-volume Move")
                : strings.localized(zh: "跨磁盘移动", en: "Cross-volume Move"),
            message: moveMessage,
            state: .warning
        ))

        if requiresAdminPrivileges {
            if prefersAdminPrivileges {
                results.append(CheckResult(title: strings.localized(zh: "将使用管理员权限", en: "Administrator Access Will Be Used"), message: strings.localized(zh: "源目录父级或目标父目录不可直接写入，执行时会请求认证。", en: "The source parent or target parent is not directly writable, so authentication will be requested during execution."), state: .warning))
            } else {
                results.append(CheckResult(title: strings.localized(zh: "缺少管理员权限", en: "Administrator Access Required"), message: strings.localized(zh: "当前路径需要管理员权限，请开启上方选项。", en: "This path requires administrator access. Turn the option above back on."), state: .fail))
            }
        } else {
            results.append(CheckResult(title: strings.localized(zh: "无需管理员权限", en: "No Administrator Access Needed"), message: strings.localized(zh: "当前目录可以直接迁移。", en: "The current folder can be migrated directly."), state: .pass))
        }

        return results
    }

    private func describeSource(snapshot: DirectorySnapshot?) -> [String] {
        guard let snapshot else {
            return [strings.notSelectedDirectory]
        }

        return [
            strings.localized(zh: "存在：\(snapshot.exists ? strings.yes : strings.no)", en: "Exists: \(snapshot.exists ? strings.yes : strings.no)"),
            strings.localized(zh: "普通目录：\(snapshot.isDirectory ? strings.yes : strings.no)", en: "Normal directory: \(snapshot.isDirectory ? strings.yes : strings.no)"),
            strings.localized(zh: "软链接：\(snapshot.isSymlink ? strings.yes : strings.no)", en: "Symbolic link: \(snapshot.isSymlink ? strings.yes : strings.no)"),
            strings.localized(
                zh: "目录大小：\(snapshot.sizeInBytes.map { Self.byteFormatterString(from: $0, locale: strings.locale) } ?? strings.unknown)",
                en: "Folder size: \(snapshot.sizeInBytes.map { Self.byteFormatterString(from: $0, locale: strings.locale) } ?? strings.unknown)"
            ),
            strings.localized(
                zh: "父目录可写：\(sourceURL.map { isWritableDirectory(at: $0.deletingLastPathComponent()) ? strings.yes : strings.no } ?? strings.unknown)",
                en: "Parent folder writable: \(sourceURL.map { isWritableDirectory(at: $0.deletingLastPathComponent()) ? strings.yes : strings.no } ?? strings.unknown)"
            )
        ]
    }

    private func describeTarget(snapshot: DirectorySnapshot?) -> [String] {
        guard let snapshot else {
            return [strings.notSelectedDirectory]
        }

        return [
            strings.localized(zh: "存在：\(snapshot.exists ? strings.yes : strings.no)", en: "Exists: \(snapshot.exists ? strings.yes : strings.no)"),
            strings.localized(zh: "可写：\(snapshot.isWritable ? strings.yes : strings.no)", en: "Writable: \(snapshot.isWritable ? strings.yes : strings.no)"),
            strings.localized(
                zh: "剩余空间：\(snapshot.availableSpace.map { Self.byteFormatterString(from: $0, locale: strings.locale) } ?? strings.unknown)",
                en: "Free space: \(snapshot.availableSpace.map { Self.byteFormatterString(from: $0, locale: strings.locale) } ?? strings.unknown)"
            )
        ]
    }

    private func snapshot(for url: URL?) async -> DirectorySnapshot? {
        guard let url else { return nil }

        let task = Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let path = url.path(percentEncoded: false)
            let exists = fm.fileExists(atPath: path)
            let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .isWritableKey
            ])

            let isDirectory = values?.isDirectory == true
            let isSymlink = values?.isSymbolicLink == true
            let freeSpace = values?.volumeAvailableCapacityForImportantUsage.flatMap { Int64(exactly: $0) }
            let isWritable = values?.isWritable == true
            let size = exists && isDirectory ? Self.directorySize(at: url) : nil

            return DirectorySnapshot(
                exists: exists,
                isDirectory: isDirectory,
                isSymlink: isSymlink,
                sizeInBytes: size,
                availableSpace: freeSpace,
                isWritable: isWritable
            )
        }

        return await task.value
    }

    nonisolated private static func moveSource(_ source: URL, toParent targetParent: URL, useAdminPrivileges: Bool) throws {
        let destination = targetParent.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        try moveItem(from: source, to: destination, useAdminPrivileges: useAdminPrivileges)
    }

    nonisolated private static func createSymlink(at source: URL, destination: URL, useAdminPrivileges: Bool) throws {
        if FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) || isDanglingSymlink(at: source) {
            try removeItemIfNeeded(at: source, useAdminPrivileges: useAdminPrivileges)
        }
        if useAdminPrivileges {
            try runShell(
                "/bin/ln -s \(Self.shellQuoted(destination.path(percentEncoded: false))) \(Self.shellQuoted(source.path(percentEncoded: false)))",
                useAdminPrivileges: true
            )
        } else {
            try FileManager.default.createSymbolicLink(at: source, withDestinationURL: destination)
        }
    }

    nonisolated private static func validateMigration(source: URL, target: URL) throws {
        let sourceValues = try source.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard sourceValues.isSymbolicLink == true else {
            throw LinkMoverError.validationFailed("原路径没有变成软链接")
        }

        var resolved = URL(fileURLWithPath: source.path(percentEncoded: false))
        resolved.resolveSymlinksInPath()
        guard resolved.standardizedFileURL == target.standardizedFileURL else {
            throw LinkMoverError.validationFailed("软链接没有指向预期目标")
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path(percentEncoded: false), isDirectory: &isDir), isDir.boolValue else {
            throw LinkMoverError.validationFailed("目标目录不存在")
        }
    }

    nonisolated private static func moveItem(from source: URL, to destination: URL, useAdminPrivileges: Bool) throws {
        if useAdminPrivileges {
            try runShell(
                "/bin/mv \(Self.shellQuoted(source.path(percentEncoded: false))) \(Self.shellQuoted(destination.path(percentEncoded: false)))",
                useAdminPrivileges: true
            )
        } else {
            try FileManager.default.moveItem(at: source, to: destination)
        }
    }

    nonisolated private static func removeItemIfNeeded(at url: URL, useAdminPrivileges: Bool) throws {
        let path = url.path(percentEncoded: false)
        if FileManager.default.fileExists(atPath: path) || isDanglingSymlink(at: url) {
            if useAdminPrivileges {
                try runShell("/bin/rm -rf \(Self.shellQuoted(path))", useAdminPrivileges: true)
            } else {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private func appendLog(_ level: LogEntry.Level, _ message: String) {
        logs.append(LogEntry(date: Date(), level: level, message: message))
    }

    private func isWritableDirectory(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isWritableKey]).isWritable) == true
    }

    nonisolated private static func isDanglingSymlink(at url: URL) -> Bool {
        ((try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true)
    }

    nonisolated private static func runShell(_ command: String, useAdminPrivileges: Bool) throws {
        if useAdminPrivileges {
            try runPrivilegedShell(command)
            return
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw LinkMoverError.shellFailed(message?.isEmpty == false ? message! : "命令执行失败")
        }
    }

    nonisolated private static func runPrivilegedShell(_ command: String) throws {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(Self.appleScriptEscaped(command))\" with administrator privileges"]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw LinkMoverError.shellFailed(message?.isEmpty == false ? message! : "管理员命令执行失败")
        }
    }

    nonisolated private static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize else {
                continue
            }
            total += Int64(fileSize)
        }
        return total
    }

    nonisolated private static func byteFormatterString(from byteCount: Int64, locale: Locale) -> String {
        _ = locale
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter
    }()

    nonisolated private static func performMigrationSteps(
        sourceURL: URL,
        targetParentURL: URL,
        destinationURL: URL,
        useAdminPrivileges: Bool,
        progress: @Sendable (LogEntry.Level, String) async -> Void
    ) async throws -> Bool {
        await progress(.info, "开始迁移：\(sourceURL.path(percentEncoded: false))")
        try moveSource(sourceURL, toParent: targetParentURL, useAdminPrivileges: useAdminPrivileges)
        await progress(.success, "目录已移动到：\(destinationURL.path(percentEncoded: false))")

        do {
            await progress(.info, "正在创建软链接...")
            try createSymlink(at: sourceURL, destination: destinationURL, useAdminPrivileges: useAdminPrivileges)
            await progress(.success, "软链接创建成功：\(sourceURL.lastPathComponent) -> \(destinationURL.path(percentEncoded: false))")

            await progress(.info, "正在校验结果...")
            try validateMigration(source: sourceURL, target: destinationURL)
            await progress(.success, "结果校验通过")
            return false
        } catch {
            await progress(.error, "目录已移动，但软链接创建失败：\(error.localizedDescription)")
            return true
        }
    }

    nonisolated private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    nonisolated private static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private enum LinkMoverError: LocalizedError {
    case validationFailed(String)
    case shellFailed(String)

    var errorDescription: String? {
        switch self {
        case let .validationFailed(message):
            return message
        case let .shellFailed(message):
            return message
        }
    }
}

private extension URL {
    var volumeIdentifierDescription: String? {
        guard let identifier = try? resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier else {
            return nil
        }
        return String(describing: identifier)
    }
}

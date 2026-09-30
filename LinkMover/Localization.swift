//
//  Localization.swift
//  LinkMover
//
//  Created by Codex on 2026/6/6.
//

import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var localeIdentifier: String { rawValue }

    var displayName: String {
        switch self {
        case .chinese: "中文"
        case .english: "English"
        }
    }
}

final class LocalizationManager: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    init() {
        if let rawValue = UserDefaults.standard.string(forKey: Self.storageKey),
           let savedLanguage = AppLanguage(rawValue: rawValue) {
            language = savedLanguage
        } else if let preferred = Locale.preferredLanguages.first,
                  preferred.lowercased().hasPrefix("en") {
            language = .english
        } else {
            language = .chinese
        }
    }

    var strings: Strings {
        Strings(language: language)
    }

    private static let storageKey = "selectedAppLanguage"
}

struct Strings {
    let language: AppLanguage

    var locale: Locale {
        Locale(identifier: language.localeIdentifier)
    }

    var appTitle: String { localized(zh: "LinkMover", en: "LinkMover") }
    var appSubtitle: String {
        localized(
            zh: "把大型目录迁移到外置磁盘，并在原路径自动创建软链接。遇到受保护目录时可自动请求管理员权限。",
            en: "Move large folders to external storage and automatically create a symbolic link at the original path. Protected locations can request administrator access when needed."
        )
    }
    var languageLabel: String { localized(zh: "语言", en: "Language") }
    var sourceDirectory: String { localized(zh: "原目录", en: "Source Folder") }
    var targetParentDirectory: String { localized(zh: "目标父目录", en: "Target Parent Folder") }
    var chooseDirectory: String { localized(zh: "选择目录", en: "Choose Folder") }
    var migrationPreview: String { localized(zh: "迁移预览", en: "Migration Preview") }
    var refreshChecks: String { localized(zh: "刷新检查", en: "Refresh Checks") }
    var finalDirectoryName: String { localized(zh: "最终目录名", en: "Final Folder Name") }
    var directoryNamePlaceholder: String { localized(zh: "目录名", en: "Folder name") }
    var requestAdminIfNeeded: String { localized(zh: "必要时请求管理员权限", en: "Request administrator access when needed") }
    var targetFullPath: String { localized(zh: "目标完整路径", en: "Full Target Path") }
    var operationPreview: String { localized(zh: "操作预览", en: "Operation Preview") }
    var preflightChecks: String { localized(zh: "迁移前检查", en: "Pre-migration Checks") }
    var activityLog: String { localized(zh: "操作日志", en: "Activity Log") }
    var restoreOriginalLocation: String { localized(zh: "恢复原位置", en: "Restore Original Location") }
    var recreateSymlink: String { localized(zh: "重新创建软链接", en: "Recreate Symbolic Link") }
    var openTargetDirectory: String { localized(zh: "打开目标目录", en: "Open Target Folder") }
    var startMigration: String { localized(zh: "开始迁移", en: "Start Migration") }
    var confirmMigrationTitle: String { localized(zh: "确认迁移目录？", en: "Confirm Folder Migration?") }
    var cancel: String { localized(zh: "取消", en: "Cancel") }
    var notSelectedDirectory: String { localized(zh: "未选择目录", en: "No folder selected") }
    var notSelectedSourceDirectory: String { localized(zh: "未选择原目录", en: "No source folder selected") }
    var notSelectedTargetParentDirectory: String { localized(zh: "未选择目标父目录", en: "No target parent folder selected") }
    var destinationPathPlaceholder: String { localized(zh: "目标路径会显示在这里", en: "The destination path will appear here") }
    var unknown: String { localized(zh: "未知", en: "Unknown") }
    var yes: String { localized(zh: "是", en: "Yes") }
    var no: String { localized(zh: "否", en: "No") }

    var pathInputPlaceholder: String { localized(zh: "输入、粘贴或从访达拖拽目录到这里", en: "Type, paste, or drop a folder here") }
    var pasteFromClipboard: String { localized(zh: "从剪贴板粘贴", en: "Paste from Clipboard") }
    var clear: String { localized(zh: "清空", en: "Clear") }
    var quickPresets: String { localized(zh: "常用目录预设", en: "Presets") }
    var advancedSettings: String { localized(zh: "高级设置与命令预览", en: "Advanced Settings & Preview") }
    var allChecksPassed: String { localized(zh: "全部检查通过", en: "All Checks Passed") }
    var checksSummaryPass: String { localized(zh: "环境检查就绪，可以安全迁移", en: "Environment is ready for migration") }
    var checksSummaryIssue: String { localized(zh: "存在阻断或需留意的检查项", en: "Issues detected, please review") }
    var showAllChecks: String { localized(zh: "明细", en: "Details") }
    var clearLogs: String { localized(zh: "清空", en: "Clear") }
    var copyLogs: String { localized(zh: "复制", en: "Copy") }
    var targetDiskSpace: String { localized(zh: "目标磁盘空间", en: "Target Disk Space") }
    var targetFreeSpace: String { localized(zh: "目标剩余", en: "Free Space") }
    var folderSize: String { localized(zh: "原目录体积", en: "Source Size") }
    var normalDirectory: String { localized(zh: "普通目录", en: "Normal Folder") }
    var writable: String { localized(zh: "可写", en: "Writable") }
    var symlink: String { localized(zh: "软链接", en: "Symlink") }
    var dragFolderHere: String { localized(zh: "释放鼠标以填入该目录", en: "Drop folder here") }
    var spaceSufficient: String { localized(zh: "空间充足", en: "Space Sufficient") }
    var spaceInsufficient: String { localized(zh: "空间不足", en: "Space Insufficient") }

    var awaitingConfiguration: String { localized(zh: "待配置迁移路径", en: "Awaiting Configuration") }
    var awaitingConfigTip: String { localized(zh: "在左侧选择或输入路径后将自动执行环境预检", en: "Select or enter paths on the left to run pre-migration checks") }
    var sourceNotSelectedGuide: String { localized(zh: "待选择原目录", en: "Awaiting Source Folder") }
    var sourceNotSelectedTip: String { localized(zh: "请在左侧选择、粘贴或拖拽要迁移的原目录。", en: "Choose, paste, or drop the source folder to migrate.") }
    var targetNotSelectedGuide: String { localized(zh: "待选择目标父目录", en: "Awaiting Target Parent Folder") }
    var targetNotSelectedTip: String { localized(zh: "请在左侧选择外置磁盘或其他目标存储位置。", en: "Choose an external disk or another target parent folder.") }

    var history: String { localized(zh: "历史记录", en: "History") }
    var historyTitle: String { localized(zh: "迁移成功历史记录", en: "Migration History") }
    var noHistory: String { localized(zh: "暂无迁移历史记录", en: "No Migration History") }
    var noHistoryTip: String { localized(zh: "成功迁移的目录将记录在此，可随时重新填入输入框或执行撤销迁移。", en: "Successfully migrated folders will be saved here. You can reload them into inputs or revert the migration at any time.") }
    var refillInputs: String { localized(zh: "填入输入框", en: "Fill Inputs") }
    var revertMigration: String { localized(zh: "撤销迁移", en: "Revert Migration") }
    var confirmRevertTitle: String { localized(zh: "确认撤销此迁移？", en: "Confirm Revert Migration?") }
    var confirmRevertMessage: String { localized(zh: "将删除软链接并将目标目录移回原路径。请确保相关应用已关闭。", en: "This will remove the symbolic link and move the target folder back to the original path. Please make sure related apps are closed.") }
    var deleteRecord: String { localized(zh: "删除记录", en: "Delete Record") }
    var clearHistory: String { localized(zh: "清空历史", en: "Clear History") }
    var confirmClearHistoryTitle: String { localized(zh: "确认清空所有历史记录？", en: "Clear All History?") }
    var confirmClearHistoryMessage: String { localized(zh: "清空历史仅移除记录，不会影响实际文件和软链接。", en: "Clearing history only removes records and will not affect actual files or symbolic links.") }
    var done: String { localized(zh: "完成", en: "Done") }
    var revealInFinder: String { localized(zh: "在访达中显示", en: "Reveal in Finder") }
    var openSourceFolder: String { localized(zh: "打开原位置", en: "Open Source Folder") }
    var openTargetFolder: String { localized(zh: "打开目标位置", en: "Open Target Folder") }
    var statusActive: String { localized(zh: "已迁移 (软链接有效)", en: "Migrated (Link Active)") }
    var statusReverted: String { localized(zh: "已撤销还原", en: "Reverted") }
    var statusTargetMissing: String { localized(zh: "目标未挂载", en: "Target Missing") }
    var statusSymlinkBroken: String { localized(zh: "软链接已失效", en: "Broken Symlink") }

    func localized(zh: String, en: String) -> String {
        switch language {
        case .chinese: zh
        case .english: en
        }
    }
}

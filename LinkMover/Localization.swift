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

    func localized(zh: String, en: String) -> String {
        switch language {
        case .chinese: zh
        case .english: en
        }
    }
}

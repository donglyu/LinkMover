//
//  ContentView.swift
//  LinkMover
//
//  Created by Leon on 2026/6/5.
//

import SwiftUI
import UniformTypeIdentifiers

struct StatusBadge: View {
    let icon: String?
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}

struct ContentView: View {
    @ObservedObject private var localization: LocalizationManager
    @StateObject private var viewModel: LinkMoverViewModel
    @State private var isShowingConfirmation = false
    @State private var isShowingAdvancedSettings = false
    @State private var isShowingCheckDetails = false
    @State private var isSourceDropTargeted = false
    @State private var isTargetDropTargeted = false

    init(localization: LocalizationManager) {
        self.localization = localization
        _viewModel = StateObject(wrappedValue: LinkMoverViewModel(localization: localization))
    }

    var body: some View {
        let strings = localization.strings
        VStack(spacing: 0) {
            header(strings)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Divider()

            // Main Two-Column Content
            HStack(alignment: .top, spacing: 16) {
                // Left Column: Configuration & Migration Flow
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 12) {
                        sourceCard(strings)
                        flowIndicator(strings)
                        targetCard(strings)
                        advancedSettingsCard(strings)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 2)
                }
                .frame(maxWidth: .infinity)

                Divider()

                // Right Column: Preflight Status & Logs
                VStack(spacing: 12) {
                    checksPanel(strings)
                    logsPanel(strings)
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 18)

            Divider()

            footer(strings)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 880, idealWidth: 940, minHeight: 620, idealHeight: 680)
        .alert(strings.confirmMigrationTitle, isPresented: $isShowingConfirmation) {
            Button(strings.cancel, role: .cancel) {}
            Button(strings.startMigration) {
                Task {
                    await viewModel.performMigration()
                }
            }
        } message: {
            Text(viewModel.confirmationMessage)
        }
        .task {
            await viewModel.refreshAll()
        }
    }

    // MARK: - Header
    private func header(_ strings: Strings) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(strings.appTitle)
                        .font(.title3.weight(.bold))
                    Text("v1.0")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Capsule())
                }
                Text(strings.appSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Picker(strings.languageLabel, selection: Binding(
                get: { localization.language },
                set: { localization.language = $0 }
            )) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
        }
    }

    // MARK: - Source Card
    private func sourceCard(_ strings: Strings) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(strings.sourceDirectory, systemImage: "folder")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Menu {
                    ForEach(viewModel.commonPresets) { preset in
                        Button(preset.title) {
                            viewModel.applyPreset(preset)
                        }
                    }
                } label: {
                    Label(strings.quickPresets, systemImage: "sparkles")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button {
                    viewModel.selectSourceDirectory()
                } label: {
                    Label(strings.chooseDirectory, systemImage: "folder.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isBusy)
            }

            // Path Input Field (Editable, Pasteable, Draggable)
            HStack(spacing: 6) {
                TextField(strings.pathInputPlaceholder, text: $viewModel.sourcePathText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit {
                        viewModel.updateSourcePath(from: viewModel.sourcePathText)
                    }

                if !viewModel.sourcePathText.isEmpty {
                    Button {
                        viewModel.clearPath(forSource: true)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(strings.clear)
                }

                Button {
                    viewModel.pasteFromClipboard(forSource: true)
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(strings.pasteFromClipboard)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSourceDropTargeted ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSourceDropTargeted ? 2 : 1)
            )
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isSourceDropTargeted) { providers in
                handleDrop(providers: providers) { path in
                    viewModel.updateSourcePath(from: path)
                }
            }

            // Source Meta Badges
            HStack(spacing: 6) {
                if let snapshot = viewModel.sourceSnapshot, snapshot.exists {
                    if let size = viewModel.sourceSizeFormatted {
                        StatusBadge(icon: "internaldrive", text: size, color: .blue)
                    }
                    StatusBadge(
                        icon: snapshot.isDirectory ? "folder" : "doc",
                        text: snapshot.isDirectory ? strings.normalDirectory : strings.localized(zh: "非普通目录", en: "Not directory"),
                        color: snapshot.isDirectory ? .secondary : .red
                    )
                    if snapshot.isSymlink {
                        StatusBadge(icon: "link", text: strings.symlink, color: .red)
                    }
                    StatusBadge(
                        icon: snapshot.isWritable ? "pencil" : "lock",
                        text: snapshot.isWritable ? strings.writable : strings.localized(zh: "只读", en: "Read-only"),
                        color: snapshot.isWritable ? .secondary : .orange
                    )
                } else if !viewModel.sourcePathText.isEmpty {
                    StatusBadge(icon: "exclamationmark.triangle", text: strings.localized(zh: "路径未找到", en: "Path not found"), color: .orange)
                } else {
                    StatusBadge(icon: "info.circle", text: strings.notSelectedSourceDirectory, color: .secondary)
                }
                Spacer()
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Flow Indicator
    private func flowIndicator(_ strings: Strings) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)

            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                if let isSame = viewModel.isSameVolume {
                    Text(isSame
                         ? strings.localized(zh: "同卷移动 (秒级指针迁移)", en: "Same Volume (Fast Rename)")
                         : strings.localized(zh: "跨卷移动 (写入外部介质)", en: "Cross Volume (Data Transfer)"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isSame ? Color.secondary : Color.orange)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
    }

    // MARK: - Target Card
    private func targetCard(_ strings: Strings) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(strings.targetParentDirectory, systemImage: "externaldrive")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button {
                    viewModel.selectTargetParentDirectory()
                } label: {
                    Label(strings.chooseDirectory, systemImage: "folder.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isBusy)
            }

            // Target Parent Path Input
            HStack(spacing: 6) {
                TextField(strings.pathInputPlaceholder, text: $viewModel.targetParentPathText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit {
                        viewModel.updateTargetParentPath(from: viewModel.targetParentPathText)
                    }

                if !viewModel.targetParentPathText.isEmpty {
                    Button {
                        viewModel.clearPath(forSource: false)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(strings.clear)
                }

                Button {
                    viewModel.pasteFromClipboard(forSource: false)
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(strings.pasteFromClipboard)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isTargetDropTargeted ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isTargetDropTargeted ? 2 : 1)
            )
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargetDropTargeted) { providers in
                handleDrop(providers: providers) { path in
                    viewModel.updateTargetParentPath(from: path)
                }
            }

            // Subfolder name input
            HStack(spacing: 8) {
                Text(strings.finalDirectoryName + ":")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                TextField(strings.directoryNamePlaceholder, text: $viewModel.destinationName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .disabled(viewModel.sourceURL == nil || viewModel.isBusy)

                if let destURL = viewModel.destinationURL {
                    Text(destURL.lastPathComponent)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            // Target Badges & Capacity Bar
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if let target = viewModel.targetSnapshot, target.exists {
                        if let free = viewModel.targetFreeSpaceFormatted {
                            StatusBadge(icon: "externaldrive", text: "\(strings.targetFreeSpace): \(free)", color: .green)
                        }
                        StatusBadge(
                            icon: target.isWritable ? "pencil" : "lock",
                            text: target.isWritable ? strings.writable : strings.localized(zh: "只读", en: "Read-only"),
                            color: target.isWritable ? .secondary : .red
                        )
                    } else if !viewModel.targetParentPathText.isEmpty {
                        StatusBadge(icon: "exclamationmark.triangle", text: strings.localized(zh: "目标未挂载", en: "Target unmounted"), color: .orange)
                    } else {
                        StatusBadge(icon: "info.circle", text: strings.notSelectedTargetParentDirectory, color: .secondary)
                    }
                    Spacer()
                }

                if let fraction = viewModel.spaceUsageFraction {
                    VStack(alignment: .leading, spacing: 3) {
                        ProgressView(value: fraction)
                            .tint(fraction > 0.9 ? .red : .accentColor)
                        HStack {
                            Text("\(strings.folderSize): \(viewModel.sourceSizeFormatted ?? "")")
                            Spacer()
                            Text(strings.localized(
                                zh: "占目标剩余空间的 \(Int(fraction * 100))%",
                                en: "\(Int(fraction * 100))% of available free space"
                            ))
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Advanced Settings Card
    private func advancedSettingsCard(_ strings: Strings) -> some View {
        DisclosureGroup(isExpanded: $isShowingAdvancedSettings) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(strings.requestAdminIfNeeded, isOn: $viewModel.prefersAdminPrivileges)
                    .toggleStyle(.switch)
                    .disabled(viewModel.isBusy)

                Text(viewModel.privilegeStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(strings.targetFullPath)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    Text(viewModel.destinationPathDisplay)
                        .font(.system(.caption2, design: .monospaced))
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(strings.operationPreview)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(strings.copyLogs) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(viewModel.previewCommand, forType: .string)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                    Text(viewModel.previewCommand)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 6)
        } label: {
            Label(strings.advancedSettings, systemImage: "gearshape")
                .font(.subheadline.weight(.semibold))
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Preflight Checks Panel
    private func checksPanel(_ strings: Strings) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(strings.preflightChecks, systemImage: "checklist")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button {
                    Task { await viewModel.refreshAll() }
                } label: {
                    Label(strings.refreshChecks, systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isBusy)
            }

            // Summary Status Banner
            let overallState = viewModel.overallCheckState
            let bannerIcon: String = {
                switch overallState {
                case .awaitingInput: return "sparkles"
                case .fail: return "xmark.circle.fill"
                case .warning: return "exclamationmark.triangle.fill"
                case .pass: return "checkmark.circle.fill"
                }
            }()
            let bannerColor: Color = {
                switch overallState {
                case .awaitingInput: return .accentColor
                case .fail: return .red
                case .warning: return .orange
                case .pass: return .green
                }
            }()
            let bannerTitle: String = {
                switch overallState {
                case .awaitingInput: return strings.awaitingConfiguration
                case .fail: return strings.localized(zh: "存在 \(viewModel.failCount) 项阻断问题", en: "\(viewModel.failCount) blocking issue(s)")
                case .warning: return strings.localized(zh: "存在 \(viewModel.warningCount) 项提示", en: "\(viewModel.warningCount) warning(s)")
                case .pass: return strings.allChecksPassed
                }
            }()
            let bannerSubtitle: String = {
                switch overallState {
                case .awaitingInput: return strings.awaitingConfigTip
                case .fail, .warning: return strings.checksSummaryIssue
                case .pass: return strings.checksSummaryPass
                }
            }()

            HStack(spacing: 10) {
                Image(systemName: bannerIcon)
                    .font(.title3)
                    .foregroundStyle(bannerColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(bannerTitle)
                        .font(.caption.weight(.semibold))

                    Text(bannerSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isShowingCheckDetails.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isShowingCheckDetails ? strings.localized(zh: "收起", en: "Hide") : strings.showAllChecks)
                        Image(systemName: isShowingCheckDetails ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption2)
                }
                .buttonStyle(.borderless)
            }
            .padding(10)
            .background(bannerColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Expandable Check Details List
            if isShowingCheckDetails || (overallState == .fail) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.checkResults) { check in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: check.symbolName)
                                    .foregroundStyle(check.color)
                                    .font(.caption)
                                    .padding(.top, 1)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(check.title)
                                        .font(.caption.weight(.medium))
                                    Text(check.message)
                                        .foregroundStyle(.secondary)
                                        .font(.caption2)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Activity Logs Panel
    private func logsPanel(_ strings: Strings) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(strings.activityLog, systemImage: "terminal")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if let activityMessage = viewModel.activityMessage {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(activityMessage)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                if let summary = viewModel.successSummary {
                    Text(summary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }

                Button(strings.copyLogs) {
                    viewModel.copyLogs()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(viewModel.logs.isEmpty)

                Button(strings.clearLogs) {
                    viewModel.clearLogs()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(viewModel.logs.isEmpty)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if viewModel.logs.isEmpty {
                            Text(strings.localized(zh: "暂无活动日志。点击开始迁移后在此输出详情。", en: "No activity logs. Migration progress will appear here."))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 20)
                        } else {
                            ForEach(viewModel.logs) { entry in
                                Text(entry.displayText)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(entry.color)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(entry.id)
                            }
                        }
                    }
                }
                .onChange(of: viewModel.logs.count) { _, _ in
                    if let lastID = viewModel.logs.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(minHeight: 140, maxHeight: .infinity)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Footer
    private func footer(_ strings: Strings) -> some View {
        HStack(spacing: 12) {
            if viewModel.canRollback {
                Button(strings.restoreOriginalLocation) {
                    Task {
                        await viewModel.rollbackMove()
                    }
                }
                .disabled(viewModel.isBusy)

                Button(strings.recreateSymlink) {
                    Task {
                        await viewModel.retrySymlinkCreation()
                    }
                }
                .disabled(viewModel.isBusy)
            }

            Spacer()

            if let targetURL = viewModel.activeTargetURL {
                Button(strings.openTargetDirectory) {
                    viewModel.openInFinder(targetURL)
                }
                .disabled(viewModel.isBusy)
            }

            Button {
                isShowingConfirmation = true
            } label: {
                HStack(spacing: 6) {
                    if viewModel.willUseAdminPrivileges {
                        Image(systemName: "lock.shield")
                    }
                    Text(strings.startMigration)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.canMigrate)
        }
    }

    // MARK: - Drag & Drop Helper
    private func handleDrop(providers: [NSItemProvider], update: @escaping (String) -> Void) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var targetURL: URL?
                if let url = item as? URL {
                    targetURL = url
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    targetURL = url
                }
                if let targetURL = targetURL {
                    DispatchQueue.main.async {
                        update(targetURL.path(percentEncoded: false))
                    }
                }
            }
            return true
        }
        return false
    }
}

#Preview {
    ContentView(localization: LocalizationManager())
}

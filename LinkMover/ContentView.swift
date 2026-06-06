//
//  ContentView.swift
//  LinkMover
//
//  Created by Leon on 2026/6/5.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var localization: LocalizationManager
    @StateObject private var viewModel: LinkMoverViewModel
    @State private var isShowingConfirmation = false

    init(localization: LocalizationManager) {
        self.localization = localization
        _viewModel = StateObject(wrappedValue: LinkMoverViewModel(localization: localization))
    }

    var body: some View {
        let strings = localization.strings
        ScrollView {
            VStack(spacing: 20) {
                header(strings)
                selectors(strings)
                destinationPreview(strings)
                checksPanel(strings)
                logsPanel(strings)
                footer(strings)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .safeAreaPadding(.top, 8)
        .frame(minWidth: 920, minHeight: 760)
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

    private func header(_ strings: Strings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(strings.appTitle)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text(strings.appSubtitle)
                        .foregroundStyle(.secondary)
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
                .frame(width: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectors(_ strings: Strings) -> some View {
        HStack(alignment: .top, spacing: 16) {
            pathCard(
                title: strings.sourceDirectory,
                path: viewModel.sourcePathDisplay,
                details: viewModel.sourceDetails,
                buttonTitle: strings.chooseDirectory
            ) {
                viewModel.selectSourceDirectory()
            }

            pathCard(
                title: strings.targetParentDirectory,
                path: viewModel.targetParentPathDisplay,
                details: viewModel.targetDetails,
                buttonTitle: strings.chooseDirectory
            ) {
                viewModel.selectTargetParentDirectory()
            }
        }
    }

    private func pathCard(
        title: String,
        path: String,
        details: [String],
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button(buttonTitle, action: action)
                    .disabled(viewModel.isBusy)
            }

            Text(path)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                ForEach(details, id: \.self) { line in
                    Text(line)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func destinationPreview(_ strings: Strings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(strings.migrationPreview)
                    .font(.headline)
                Spacer()
                Button(strings.refreshChecks) {
                    Task { await viewModel.refreshAll() }
                }
                .disabled(viewModel.isBusy)
            }

            Text(strings.finalDirectoryName)
                .foregroundStyle(.secondary)

            TextField(strings.directoryNamePlaceholder, text: $viewModel.destinationName)
                .textFieldStyle(.roundedBorder)
                .disabled(viewModel.sourceURL == nil || viewModel.isBusy)

            Toggle(strings.requestAdminIfNeeded, isOn: $viewModel.prefersAdminPrivileges)
                .toggleStyle(.switch)
                .disabled(viewModel.isBusy)

            Text(viewModel.privilegeStatusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)

            LabeledContent(strings.targetFullPath) {
                Text(viewModel.destinationPathDisplay)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }

            LabeledContent(strings.operationPreview) {
                Text(viewModel.previewCommand)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func checksPanel(_ strings: Strings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(strings.preflightChecks)
                .font(.headline)

            ForEach(viewModel.checkResults) { check in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: check.symbolName)
                        .foregroundStyle(check.color)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(check.title)
                        Text(check.message)
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func logsPanel(_ strings: Strings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(strings.activityLog)
                    .font(.headline)
                Spacer()
                if let activityMessage = viewModel.activityMessage {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(activityMessage)
                    }
                    .foregroundStyle(.secondary)
                }
                if let summary = viewModel.successSummary {
                    Text(summary)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.logs) { entry in
                        Text(entry.displayText)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(entry.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(minHeight: 180)
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

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

            Button(strings.startMigration) {
                isShowingConfirmation = true
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.canMigrate)
        }
    }
}

#Preview {
    ContentView(localization: LocalizationManager())
}

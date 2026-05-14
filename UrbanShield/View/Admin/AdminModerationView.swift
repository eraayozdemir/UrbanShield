//
//  AdminModerationView.swift
//  UrbanShield
//

import SwiftUI

struct AdminModerationView: View {
    let sessionViewModel: AuthSessionViewModel

    @State private var viewModel = AdminModerationViewModel()
    @State private var selectedFilter: AdminModerationFilter = .active

    private var currentUser: User? {
        if case .authenticated(let user) = sessionViewModel.session {
            return user
        }
        return nil
    }

    private var filteredRows: [AdminModerationRow] {
        viewModel.rows.filter { selectedFilter.includes($0.report.statusValue) }
    }

    var body: some View {
        ZStack {
            RequestUI.background
                .ignoresSafeArea()

            if viewModel.isLoading && viewModel.rows.isEmpty {
                AdminModerationLoadingView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        header
                            .padding(.top, 8)

                        metricsGrid
                        filterBar
                        moderationNoteCard

                        if filteredRows.isEmpty {
                            emptyState
                        } else {
                            ForEach(filteredRows) { row in
                                AdminModerationCard(
                                    row: row,
                                    isUpdating: viewModel.updatingReportId == row.report.id,
                                    isCancelling: row.request?.id == viewModel.cancellingRequestId
                                ) { status in
                                    Task {
                                        await viewModel.updateReportStatus(
                                            row: row,
                                            status: status,
                                            currentUser: currentUser
                                        )
                                    }
                                } onCancelRequest: {
                                    Task {
                                        await viewModel.cancelLinkedRequest(
                                            row: row,
                                            currentUser: currentUser
                                        )
                                    }
                                }
                            }
                        }

                        recentActions
                    }
                    .padding(16)
                    .padding(.bottom, 18)
                }
                .refreshable {
                    await reloadModeration()
                }
            }
        }
        .navigationTitle("Moderation")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await reloadModeration() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .overlay(alignment: .bottom) {
            if let error = viewModel.errorMessage {
                RequestErrorBanner(message: error)
            } else if let success = viewModel.successMessage {
                RequestInfoBanner(message: success, color: .green)
            }
        }
        .task {
            await reloadModeration()
        }
    }

    private func reloadModeration() async {
        await viewModel.load(currentUser: currentUser)
    }

    private var header: some View {
        RequestCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Reports & Moderation")
                        .font(.title2.bold())

                    Text("Review suspicious activity reports, resolve abuse cases, and cancel unsafe linked requests.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            AdminModerationMetricCard(title: "Open", value: viewModel.openCount, systemImage: "flag.fill", color: .red)
            AdminModerationMetricCard(title: "Review", value: viewModel.reviewingCount, systemImage: "eye.fill", color: .orange)
            AdminModerationMetricCard(title: "Resolved", value: viewModel.resolvedCount, systemImage: "checkmark.seal.fill", color: .green)
        }
    }

    private var filterBar: some View {
        Picker("Moderation Filter", selection: $selectedFilter) {
            ForEach(AdminModerationFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }

    private var moderationNoteCard: some View {
        RequestCard {
            RequestSectionTitle(title: "Action Note", systemImage: "note.text")

            TextField("Optional note for the next moderation action", text: $viewModel.moderationNote, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.sentences)
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Reports",
            systemImage: "checkmark.shield",
            description: Text("No moderation reports match the selected filter.")
        )
        .padding(.vertical, 40)
    }

    private var recentActions: some View {
        RequestCard {
            RequestSectionTitle(title: "Recent Moderation Actions", systemImage: "clock.arrow.circlepath")

            if viewModel.actions.isEmpty {
                Label("No moderation actions logged yet.", systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(viewModel.actions.prefix(8)) { action in
                    ModerationActionRow(action: action)
                    if action.id != viewModel.actions.prefix(8).last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

private enum AdminModerationFilter: String, CaseIterable, Identifiable {
    case active
    case open
    case reviewing
    case closed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "Active"
        case .open: return "Open"
        case .reviewing: return "Review"
        case .closed: return "Closed"
        }
    }

    func includes(_ status: SuspiciousReportStatus) -> Bool {
        switch self {
        case .active:
            return status == .open || status == .reviewing
        case .open:
            return status == .open
        case .reviewing:
            return status == .reviewing
        case .closed:
            return status == .resolved || status == .dismissed
        }
    }
}

private struct AdminModerationMetricCard: View {
    let title: String
    let value: Int
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text("\(value)")
                .font(.headline)
                .monospacedDigit()

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RequestUI.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AdminModerationCard: View {
    let row: AdminModerationRow
    let isUpdating: Bool
    let isCancelling: Bool
    let onStatusChange: (SuspiciousReportStatus) -> Void
    let onCancelRequest: () -> Void

    var body: some View {
        RequestCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.headline)
                    .foregroundStyle(statusColor)
                    .frame(width: 42, height: 42)
                    .background(statusColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(row.report.categoryValue.title)
                        .font(.headline)

                    Text(row.report.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusChip
            }

            Text(row.report.details)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                AdminModerationInfoRow(
                    title: "Reporter",
                    value: reporterText,
                    systemImage: "person.crop.circle.fill"
                )

                AdminModerationInfoRow(
                    title: "Linked Request",
                    value: requestText,
                    systemImage: "doc.text.magnifyingglass"
                )
            }

            HStack(spacing: 10) {
                Menu {
                    ForEach(SuspiciousReportStatus.allCases) { status in
                        Button(status.title) {
                            onStatusChange(status)
                        }
                    }
                } label: {
                    if isUpdating {
                        ProgressView()
                    } else {
                        Label("Status", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                    }
                }
                .disabled(isUpdating)

                if row.request?.statusValue.canBeCancelled == true {
                    Button(role: .destructive) {
                        onCancelRequest()
                    } label: {
                        if isCancelling {
                            ProgressView()
                        } else {
                            Label("Cancel Request", systemImage: "xmark.circle.fill")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .disabled(isCancelling)
                }

                Spacer()
            }
        }
    }

    private var reporterText: String {
        guard let reporter = row.reporter else {
            return "User \(row.report.reporterId.uuidString.prefix(8))"
        }
        return "\(reporter.fullName) • \(reporter.email)"
    }

    private var requestText: String {
        guard let request = row.request else {
            return row.report.requestId.map { "Request \($0.uuidString.prefix(8))" } ?? "No linked request"
        }
        return "\(request.requestTypeValue.title) • \(request.statusValue.title)"
    }

    private var statusChip: some View {
        Text(row.report.statusValue.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.12))
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch row.report.statusValue {
        case .open: return .red
        case .reviewing: return .orange
        case .resolved: return .green
        case .dismissed: return .gray
        }
    }
}

private struct AdminModerationInfoRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.purple)
                .frame(width: 30, height: 30)
                .background(Color.purple.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct ModerationActionRow: View {
    let action: ModerationActionRecord

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(action.actionValue.title)
                    .font(.subheadline.weight(.semibold))

                Text(action.notes ?? "No note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(action.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var icon: String {
        switch action.actionValue {
        case .statusUpdated: return "arrow.triangle.2.circlepath"
        case .requestCancelled: return "xmark.circle.fill"
        case .reportResolved: return "checkmark.seal.fill"
        case .reportDismissed: return "minus.circle.fill"
        case .noteAdded: return "note.text"
        }
    }

    private var color: Color {
        switch action.actionValue {
        case .statusUpdated: return .blue
        case .requestCancelled: return .red
        case .reportResolved: return .green
        case .reportDismissed: return .gray
        case .noteAdded: return .purple
        }
    }
}

private struct AdminModerationLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading moderation reports...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

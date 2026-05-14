//
//  CoordinatorOperationsView.swift
//  UrbanShield
//

import SwiftUI

struct CoordinatorOperationsView: View {
    let sessionViewModel: AuthSessionViewModel

    @State private var viewModel = CoordinatorOperationsViewModel()
    @State private var selectedTool: CoordinatorOperationTool = .supply

    private var currentUser: User? {
        if case .authenticated(let user) = sessionViewModel.session {
            return user
        }
        return nil
    }

    var body: some View {
        ZStack {
            RequestUI.background
                .ignoresSafeArea()

            if viewModel.isLoading && viewModel.activeRequests.isEmpty {
                CoordinatorToolsLoadingView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        header
                            .padding(.top, 8)

                        toolPicker

                        switch selectedTool {
                        case .supply:
                            supplySection
                        case .announcements:
                            announcementSection
                        case .reports:
                            suspiciousReportSection
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 18)
                }
                .refreshable {
                    await reloadTools()
                }
            }
        }
        .navigationTitle("Tools")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await reloadTools() }
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
            await reloadTools()
        }
    }

    private func reloadTools() async {
        await viewModel.load(currentUser: currentUser)
    }

    private var header: some View {
        RequestCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "cross.case.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.teal)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Coordination Tools")
                        .font(.title2.bold())

                    Text("Log resource support, publish emergency announcements, and report suspicious activity.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var toolPicker: some View {
        Picker("Tool", selection: $selectedTool) {
            ForEach(CoordinatorOperationTool.allCases) { tool in
                Text(tool.title).tag(tool)
            }
        }
        .pickerStyle(.segmented)
    }

    private var supplySection: some View {
        Group {
            RequestCard {
                RequestSectionTitle(title: "Supply Support", systemImage: "shippingbox.fill")

                RequestSelectionMenu(
                    title: "Request",
                    selectionTitle: viewModel.requestTitle(for: viewModel.selectedSupplyRequestId),
                    requests: viewModel.activeRequests
                ) { request in
                    viewModel.selectedSupplyRequestId = request?.id
                }

                Picker("Support Type", selection: $viewModel.supplyType) {
                    ForEach(SupplySupportType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }

                Picker("Status", selection: $viewModel.supplyStatus) {
                    ForEach(SupplyActionStatus.allCases) { status in
                        Text(status.title).tag(status)
                    }
                }

                TextField("Quantity or package details", text: $viewModel.supplyQuantity)
                    .textInputAutocapitalization(.sentences)
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                TextField("Notes", text: $viewModel.supplyNotes, axis: .vertical)
                    .lineLimit(2...4)
                    .textInputAutocapitalization(.sentences)
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                RequestPrimaryButton(
                    title: "Log Support",
                    systemImage: "plus.circle.fill",
                    isLoading: viewModel.isSavingSupply
                ) {
                    Task { await viewModel.createSupplyAction(currentUser: currentUser) }
                }
            }

            recentSupplyActions
        }
    }

    private var announcementSection: some View {
        Group {
            RequestCard {
                RequestSectionTitle(title: "Emergency Announcement", systemImage: "megaphone.fill")

                Picker("Severity", selection: $viewModel.announcementSeverity) {
                    ForEach(EmergencyAnnouncementSeverity.allCases) { severity in
                        Text(severity.title).tag(severity)
                    }
                }

                Picker("Audience", selection: $viewModel.announcementAudience) {
                    ForEach(EmergencyAnnouncementAudience.allCases) { audience in
                        Text(audience.title).tag(audience)
                    }
                }

                TextField("Title", text: $viewModel.announcementTitle)
                    .textInputAutocapitalization(.sentences)
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                TextField("Message", text: $viewModel.announcementMessage, axis: .vertical)
                    .lineLimit(3...6)
                    .textInputAutocapitalization(.sentences)
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                RequestPrimaryButton(
                    title: "Publish Announcement",
                    systemImage: "paperplane.fill",
                    isLoading: viewModel.isPublishingAnnouncement
                ) {
                    Task { await viewModel.publishAnnouncement(currentUser: currentUser) }
                }
            }

            recentAnnouncements
        }
    }

    private var suspiciousReportSection: some View {
        Group {
            RequestCard {
                RequestSectionTitle(title: "Suspicious Activity", systemImage: "exclamationmark.shield.fill")

                Text("Coordinators can submit suspicious activity reports. Admin users review and moderate reports from the admin moderation panel.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                NavigationLink {
                    SuspiciousActivityReportView(sessionViewModel: sessionViewModel)
                } label: {
                    Label("Create Suspicious Report", systemImage: "flag.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
            }

            recentSuspiciousReports
        }
    }

    private var recentSupplyActions: some View {
        RequestCard {
            RequestSectionTitle(title: "Recent Support Actions", systemImage: "clock.fill")

            if viewModel.supplyActions.isEmpty {
                EmptyToolRow(title: "No support logged yet.", systemImage: "shippingbox")
            } else {
                ForEach(viewModel.supplyActions.prefix(8)) { action in
                    SupplyActionRow(action: action, requestTitle: viewModel.requestTitle(for: action.requestId))
                    if action.id != viewModel.supplyActions.prefix(8).last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var recentAnnouncements: some View {
        RequestCard {
            RequestSectionTitle(title: "Recent Announcements", systemImage: "bell.badge.fill")

            if viewModel.announcements.isEmpty {
                EmptyToolRow(title: "No announcements published yet.", systemImage: "megaphone")
            } else {
                ForEach(viewModel.announcements.prefix(8)) { announcement in
                    AnnouncementRow(announcement: announcement)
                    if announcement.id != viewModel.announcements.prefix(8).last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var recentSuspiciousReports: some View {
        RequestCard {
            RequestSectionTitle(title: "My Recent Reports", systemImage: "tray.full.fill")

            if viewModel.suspiciousReports.isEmpty {
                EmptyToolRow(title: "No suspicious activity reports yet.", systemImage: "flag")
            } else {
                ForEach(viewModel.suspiciousReports.prefix(8)) { report in
                    CoordinatorReportReadonlyRow(
                        report: report,
                        requestTitle: viewModel.requestTitle(for: report.requestId)
                    )
                    if report.id != viewModel.suspiciousReports.prefix(8).last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

private enum CoordinatorOperationTool: String, CaseIterable, Identifiable {
    case supply
    case announcements
    case reports

    var id: String { rawValue }

    var title: String {
        switch self {
        case .supply: return "Supply"
        case .announcements: return "Alerts"
        case .reports: return "Reports"
        }
    }
}

private struct RequestSelectionMenu: View {
    let title: String
    let selectionTitle: String
    let requests: [HelpRequestRecord]
    var includesNone = false
    let onSelect: (HelpRequestRecord?) -> Void

    var body: some View {
        Menu {
            if includesNone {
                Button("No linked request") {
                    onSelect(nil)
                }
            }

            if requests.isEmpty {
                Text("No active requests")
            } else {
                ForEach(requests) { request in
                    Button {
                        onSelect(request)
                    } label: {
                        Label(
                            "\(request.requestTypeValue.title) • \(request.statusValue.title)",
                            systemImage: RequestUI.requestIcon(request.requestTypeValue)
                        )
                    }
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(selectionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.down.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SupplyActionRow: View {
    let action: SupplySupportActionRecord
    let requestTitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ToolIcon(systemImage: "shippingbox.fill", color: color)

            VStack(alignment: .leading, spacing: 4) {
                Text(action.supportTypeValue.title)
                    .font(.subheadline.weight(.semibold))

                Text(requestTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let quantity = action.quantity, !quantity.isEmpty {
                    Text(quantity)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(action.statusValue.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.vertical, 8)
    }

    private var color: Color {
        switch action.statusValue {
        case .planned: return .blue
        case .dispatched: return .orange
        case .delivered: return .green
        case .cancelled: return .red
        }
    }
}

private struct AnnouncementRow: View {
    let announcement: EmergencyAnnouncementRecord

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ToolIcon(systemImage: "megaphone.fill", color: color)

            VStack(alignment: .leading, spacing: 4) {
                Text(announcement.title)
                    .font(.subheadline.weight(.semibold))

                Text(announcement.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text("\(announcement.audienceValue.title) • \(announcement.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(announcement.severityValue.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.vertical, 8)
    }

    private var color: Color {
        switch announcement.severityValue {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

private struct CoordinatorReportReadonlyRow: View {
    let report: SuspiciousActivityReportRecord
    let requestTitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ToolIcon(systemImage: "exclamationmark.shield.fill", color: color)

            VStack(alignment: .leading, spacing: 4) {
                Text(report.categoryValue.title)
                    .font(.subheadline.weight(.semibold))

                Text(report.details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(requestTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(report.statusValue.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.vertical, 8)
    }

    private var color: Color {
        switch report.statusValue {
        case .open: return .red
        case .reviewing: return .orange
        case .resolved: return .green
        case .dismissed: return .gray
        }
    }
}

private struct ToolIcon: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline)
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct EmptyToolRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }
}

private struct CoordinatorToolsLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading coordination tools...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

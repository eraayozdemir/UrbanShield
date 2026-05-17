//
//  AdminActivityLogView.swift
//  UrbanShield
//

import SwiftUI

struct AdminActivityLogView: View {
    let sessionViewModel: AuthSessionViewModel

    @State private var viewModel = AdminActivityLogViewModel()
    @State private var isRoleFilterExpanded = true
    @State private var isActionFilterExpanded = false

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

            if viewModel.isLoading && viewModel.logs.isEmpty {
                ActivityLoadingView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        header
                            .padding(.top, 8)

                        metrics
                        filters

                        if viewModel.filteredLogs.isEmpty {
                            ContentUnavailableView(
                                "No Activity",
                                systemImage: "clock.badge.questionmark",
                                description: Text("No activity logs match the current filters.")
                            )
                            .padding(.vertical, 40)
                        } else {
                            ForEach(viewModel.filteredLogs) { log in
                                ActivityLogCard(
                                    log: log,
                                    actorName: viewModel.actorName(for: log),
                                    targetUserName: viewModel.targetUserName(for: log),
                                    requestIdText: viewModel.shortId(log.requestId),
                                    reportIdText: viewModel.shortId(log.reportId),
                                    targetIdText: viewModel.shortId(log.targetId)
                                )
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 18)
                }
                .refreshable {
                    await reload()
                }
            }
        }
        .navigationTitle("Activity")
        .searchable(text: $viewModel.searchText, prompt: "Search logs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .overlay(alignment: .bottom) {
            if let error = viewModel.errorMessage {
                RequestErrorBanner(message: error)
            }
        }
        .task {
            await reload()
        }
    }

    private func reload() async {
        await viewModel.load(currentUser: currentUser)
    }

    private var header: some View {
        RequestCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "clock.arrow.2.circlepath")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.indigo)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Activity Logs")
                        .font(.title2.bold())

                    Text("Audit request, volunteer, coordinator, report, and admin moderation actions.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ActivityMetricCard(title: "Today", value: viewModel.todayCount, systemImage: "calendar.badge.clock", color: .blue)
            ActivityMetricCard(title: "Admin", value: viewModel.adminActionCount, systemImage: "crown.fill", color: .purple)
            ActivityMetricCard(title: "Requests", value: viewModel.requestActionCount, systemImage: "list.bullet.rectangle.fill", color: .orange)
        }
    }

    private var filters: some View {
        RequestCard {
            HStack {
                RequestSectionTitle(title: "Filters", systemImage: "line.3.horizontal.decrease.circle.fill")

                Spacer()

                if viewModel.hasActiveFilters {
                    Button {
                        withAnimation(.snappy) {
                            viewModel.resetFilters()
                        }
                    } label: {
                        Label("Clear", systemImage: "xmark.circle.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
            }

            VStack(spacing: 12) {
                ActivityFilterDisclosure(
                    title: "Role",
                    value: viewModel.selectedRole.title,
                    systemImage: "person.2.fill",
                    isExpanded: $isRoleFilterExpanded
                ) {
                    VStack(spacing: 0) {
                        ForEach(ActivityRoleFilter.allCases) { filter in
                            ActivityFilterOptionRow(
                                title: filter.title,
                                subtitle: roleSubtitle(for: filter),
                                systemImage: roleIcon(for: filter),
                                color: roleColor(for: filter),
                                isSelected: filter == viewModel.selectedRole
                            ) {
                                withAnimation(.snappy) {
                                    viewModel.selectedRole = filter
                                    isRoleFilterExpanded = false
                                }
                            }

                            if filter != ActivityRoleFilter.allCases.last {
                                Divider()
                                    .padding(.leading, 46)
                            }
                        }
                    }
                }

                ActivityFilterDisclosure(
                    title: "Action",
                    value: viewModel.selectedAction.title,
                    systemImage: "bolt.horizontal.circle.fill",
                    isExpanded: $isActionFilterExpanded
                ) {
                    VStack(spacing: 0) {
                        ForEach(ActivityActionFilter.allCases) { filter in
                            ActivityFilterOptionRow(
                                title: filter.title,
                                subtitle: actionSubtitle(for: filter),
                                systemImage: actionIcon(for: filter),
                                color: actionColor(for: filter),
                                isSelected: filter == viewModel.selectedAction
                            ) {
                                withAnimation(.snappy) {
                                    viewModel.selectedAction = filter
                                    isActionFilterExpanded = false
                                }
                            }

                            if filter != ActivityActionFilter.allCases.last {
                                Divider()
                                    .padding(.leading, 46)
                            }
                        }
                    }
                }
            }
        }
    }

    private func roleSubtitle(for filter: ActivityRoleFilter) -> String {
        switch filter {
        case .all: return "Show every user role"
        case .citizen: return "Citizen-created activity"
        case .volunteer: return "Volunteer task activity"
        case .coordinator: return "Coordinator operations"
        case .admin: return "Admin moderation and role changes"
        }
    }

    private func roleIcon(for filter: ActivityRoleFilter) -> String {
        switch filter {
        case .all: return "person.3.fill"
        case .citizen: return "person.fill"
        case .volunteer: return "checkmark.shield.fill"
        case .coordinator: return "rectangle.grid.2x2.fill"
        case .admin: return "crown.fill"
        }
    }

    private func roleColor(for filter: ActivityRoleFilter) -> Color {
        switch filter {
        case .all: return .blue
        case .citizen: return .blue
        case .volunteer: return .green
        case .coordinator: return .orange
        case .admin: return .purple
        }
    }

    private func actionSubtitle(for filter: ActivityActionFilter) -> String {
        switch filter {
        case .all: return "Show every action"
        case .requests: return "Create, cancel, status, and priority"
        case .assignments: return "Volunteer assignment activity"
        case .reports: return "Suspicious report activity"
        case .operations: return "Supply, announcements, and roles"
        }
    }

    private func actionIcon(for filter: ActivityActionFilter) -> String {
        switch filter {
        case .all: return "square.grid.2x2.fill"
        case .requests: return "list.bullet.rectangle.fill"
        case .assignments: return "person.crop.circle.badge.checkmark"
        case .reports: return "flag.fill"
        case .operations: return "gearshape.2.fill"
        }
    }

    private func actionColor(for filter: ActivityActionFilter) -> Color {
        switch filter {
        case .all: return .indigo
        case .requests: return .orange
        case .assignments: return .teal
        case .reports: return .red
        case .operations: return .purple
        }
    }
}

private struct ActivityFilterDisclosure<Content: View>: View {
    let title: String
    let value: String
    let systemImage: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                        .frame(width: 34, height: 34)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(value)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    content
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct ActivityFilterOptionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(color)
                    .frame(width: 34, height: 34)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.headline)
                    .foregroundStyle(isSelected ? color : Color.secondary.opacity(0.35))
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

private struct ActivityMetricCard: View {
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

private struct ActivityLogCard: View {
    let log: ActivityLogRecord
    let actorName: String
    let targetUserName: String?
    let requestIdText: String
    let reportIdText: String
    let targetIdText: String

    var body: some View {
        RequestCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(color)
                    .frame(width: 38, height: 38)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(log.actionValue?.title ?? log.actionType)
                            .font(.headline)

                        Spacer()

                        Text(log.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(log.message)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("\(actorName) • \(log.actorRole.capitalized)", systemImage: "person.fill")

                        if log.requestId != nil {
                            Label("Request \(requestIdText)", systemImage: "list.bullet.rectangle.fill")
                        }

                        if log.reportId != nil {
                            Label("Report \(reportIdText)", systemImage: "flag.fill")
                        }

                        if let targetUserName {
                            Label("Target \(targetUserName)", systemImage: "person.crop.circle.badge.exclamationmark")
                        } else if log.targetId != nil {
                            Label("Target \(targetIdText)", systemImage: "scope")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var icon: String {
        switch log.actionValue {
        case .requestCreated: return "plus.circle.fill"
        case .requestUpdated: return "square.and.pencil"
        case .requestCancelled: return "xmark.circle.fill"
        case .requestConfirmed: return "checkmark.shield.fill"
        case .requestStarted: return "play.circle.fill"
        case .requestCompleted: return "checkmark.seal.fill"
        case .requestStatusUpdated: return "arrow.triangle.2.circlepath"
        case .requestPriorityUpdated: return "exclamationmark.triangle.fill"
        case .volunteerAssigned: return "person.crop.circle.badge.checkmark"
        case .supplySupportLogged: return "shippingbox.fill"
        case .announcementPublished: return "megaphone.fill"
        case .suspiciousReportSubmitted: return "flag.fill"
        case .suspiciousReportReviewed: return "shield.lefthalf.filled.badge.checkmark"
        case .roleUpdated: return "person.badge.key.fill"
        case .evidenceUploaded: return "photo.badge.plus.fill"
        case nil: return "clock.fill"
        }
    }

    private var color: Color {
        switch log.actionValue {
        case .requestCreated, .requestUpdated, .requestConfirmed, .requestStarted: return .blue
        case .requestCompleted: return .green
        case .requestCancelled: return .red
        case .requestStatusUpdated, .requestPriorityUpdated: return .orange
        case .volunteerAssigned: return .teal
        case .supplySupportLogged: return .brown
        case .announcementPublished: return .purple
        case .suspiciousReportSubmitted, .suspiciousReportReviewed: return .red
        case .roleUpdated: return .indigo
        case .evidenceUploaded: return .cyan
        case nil: return .gray
        }
    }
}

private struct ActivityLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading activity logs...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

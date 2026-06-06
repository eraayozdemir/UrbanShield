//
//  CoordinatorDashboardView.swift
//  UrbanShield
//

import SwiftUI

struct CoordinatorDashboardView: View {
    let sessionViewModel: AuthSessionViewModel

    // Dashboard ViewModel Supabase yükleme işlemlerini, status güncellemelerini,
    // volunteer atamalarını ve son coordination loglarını yönetir.
    @State private var viewModel = CoordinatorDashboardViewModel()
    @State private var selectedFilter: CoordinatorRequestFilter = .active

    private var currentUser: User? {
        if case .authenticated(let user) = sessionViewModel.session {
            return user
        }
        return nil
    }

    private var filteredRequests: [HelpRequestRecord] {
        // Dashboard sekmeleri/kartları için lokal status filtresi.
        viewModel.requests.filter { selectedFilter.includes($0.statusValue) }
    }

    private var activeRequests: [HelpRequestRecord] {
        viewModel.requests.filter { $0.statusValue.isActive }
    }

    private var criticalUrgencyCount: Int {
        viewModel.requests.filter { $0.urgencyValue == .critical && $0.statusValue.isActive }.count
    }

    private var unassignedCount: Int {
        viewModel.requests.filter { $0.statusValue == .open }.count
    }

    var body: some View {
        ZStack {
            RequestUI.background
                .ignoresSafeArea()

            if viewModel.isLoading && viewModel.requests.isEmpty {
                CoordinatorLoadingView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        // Başlık coordinator işlevini özetler.
                        dashboardHeader
                            .padding(.top, 8)

                        metricsGrid

                        if !viewModel.activityLogs.isEmpty {
                            // En son coordination log kayıtlarını gösterir.
                            recentActivity
                        }

                        filterBar

                        if filteredRequests.isEmpty {
                            emptyState
                        } else {
                            // Coordinator kartları detay ekranına girmeden doğrudan status değişimini
                            // ve volunteer atamasını destekler.
                            ForEach(filteredRequests) { request in
                                NavigationLink {
                                    RequestDetailView(
                                        requestId: request.id,
                                        sessionViewModel: sessionViewModel
                                    )
                                } label: {
                                    CoordinatorRequestCard(
                                        request: request,
                                        eligibleVolunteers: viewModel.eligibleVolunteers(for: request),
                                        activeVolunteerCount: viewModel.activeVolunteerCount(for: request),
                                        statusTargets: viewModel.allowedStatusTargets(for: request),
                                        isUpdating: viewModel.updatingRequestId == request.id
                                    ) { status in
                                        Task {
                                            await viewModel.updateStatus(
                                                request: request,
                                                status: status,
                                                currentUser: currentUser
                                            )
                                            await sessionViewModel.refreshCurrentUser()
                                        }
                                    } onAssignVolunteer: { volunteer in
                                        Task {
                                            await viewModel.assignVolunteer(
                                                request: request,
                                                volunteer: volunteer,
                                                currentUser: currentUser
                                            )
                                            await sessionViewModel.refreshCurrentUser()
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 18)
                }
                .refreshable {
                    await reloadDashboard()
                }
            }
        }
        .navigationTitle("Coordinator")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await reloadDashboard() }
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
            // İlk dashboard yüklemesi ve realtime aboneliği.
            await reloadDashboard()
            await viewModel.startRealtime(currentUser: currentUser)
        }
        .onDisappear {
            viewModel.stopRealtime()
        }
    }

    private func reloadDashboard() async {
        await viewModel.loadRequests(currentUser: currentUser)
        await sessionViewModel.refreshCurrentUser()
    }

    private var recentActivity: some View {
        RequestCard {
            HStack {
                RequestSectionTitle(title: "Recent Activity", systemImage: "clock.arrow.circlepath")
                Spacer()
                Text("\(viewModel.activityLogs.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(viewModel.activityLogs.prefix(4).enumerated()), id: \.element.id) { index, log in
                    CoordinatorActivityRow(log: log)
                    if index < min(viewModel.activityLogs.count, 4) - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private var dashboardHeader: some View {
        RequestCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "rectangle.grid.2x2.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Response Dashboard")
                        .font(.title2.bold())

                    Text("Monitor active requests and coordinate the response queue.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            CoordinatorMetricCard(
                title: "Active",
                value: "\(activeRequests.count)",
                systemImage: "bolt.fill",
                color: .orange
            )

            CoordinatorMetricCard(
                title: "Critical",
                value: "\(criticalUrgencyCount)",
                systemImage: "flag.fill",
                color: .red
            )

            CoordinatorMetricCard(
                title: "Open",
                value: "\(unassignedCount)",
                systemImage: "person.2.badge.gearshape.fill",
                color: .blue
            )

            CoordinatorMetricCard(
                title: "Total",
                value: "\(viewModel.requests.count)",
                systemImage: "tray.full.fill",
                color: .green
            )
        }
    }

    private var filterBar: some View {
        Picker("Request Filter", selection: $selectedFilter) {
            ForEach(CoordinatorRequestFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Requests",
            systemImage: "checkmark.shield",
            description: Text("No requests match the selected coordinator filter.")
        )
        .padding(.vertical, 40)
    }
}

private enum CoordinatorRequestFilter: String, CaseIterable, Identifiable {
    case active
    case open
    case progress
    case closed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "Active"
        case .open: return "Open"
        case .progress: return "Progress"
        case .closed: return "Closed"
        }
    }

    func includes(_ status: HelpRequestStatus) -> Bool {
        switch self {
        case .active:
            return status.isActive
        case .open:
            return status == .open
        case .progress:
            return status == .confirmed || status == .inProgress
        case .closed:
            return status == .completed || status == .cancelled
        }
    }
}

private struct CoordinatorMetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(value)
                .font(.title2.bold())
                .monospacedDigit()

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RequestUI.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CoordinatorRequestCard: View {
    let request: HelpRequestRecord
    let eligibleVolunteers: [ProfileUserRecord]
    let activeVolunteerCount: Int
    let statusTargets: [HelpRequestStatus]
    let isUpdating: Bool
    let onStatusChange: (HelpRequestStatus) -> Void
    let onAssignVolunteer: (ProfileUserRecord) -> Void

    var body: some View {
        RequestCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: RequestUI.requestIcon(request.requestTypeValue))
                    .font(.headline)
                    .foregroundStyle(RequestUI.urgencyColor(request.urgencyValue))
                    .frame(width: 42, height: 42)
                    .background(RequestUI.urgencyColor(request.urgencyValue).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(request.requestTypeValue.title)
                        .font(.headline)

                    Text(request.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                RequestStatusChip(status: request.statusValue)
            }

            Text(request.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                RequestUrgencyChip(urgency: request.urgencyValue)
                Label("\(activeVolunteerCount)/\(request.volunteerCapacity)", systemImage: "person.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(Capsule())
                Spacer()
            }

            HStack(spacing: 10) {
                Label(coordinateText, systemImage: "location.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer()

                if !statusTargets.isEmpty {
                    Menu {
                        ForEach(statusTargets) { status in
                            Button {
                                onStatusChange(status)
                            } label: {
                                Label(status.title, systemImage: statusIcon(for: status))
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
                }

                if request.statusValue.acceptsVolunteers {
                    Menu {
                        if eligibleVolunteers.isEmpty {
                            Text("No matching volunteers")
                        } else {
                            ForEach(eligibleVolunteers) { volunteer in
                                Button {
                                    onAssignVolunteer(volunteer)
                                } label: {
                                    Label(volunteer.fullName, systemImage: "person.crop.circle.badge.checkmark")
                                }
                            }
                        }
                    } label: {
                        if isUpdating {
                            ProgressView()
                        } else {
                            Label("Assign", systemImage: "person.badge.plus")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .disabled(isUpdating || eligibleVolunteers.isEmpty)
                }

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var coordinateText: String {
        let latitude = request.latitude.formatted(.number.precision(.fractionLength(2...4)))
        let longitude = request.longitude.formatted(.number.precision(.fractionLength(2...4)))
        return "\(latitude), \(longitude)"
    }

    private func statusIcon(for status: HelpRequestStatus) -> String {
        switch status {
        case .open: return "circle"
        case .confirmed: return "checkmark.shield.fill"
        case .inProgress: return "figure.run"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }
}

private struct CoordinatorActivityRow: View {
    let log: CoordinationLogRecord

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(log.message)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                Text("\(log.actionValue.title) • \(log.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 10)
    }

    private var icon: String {
        switch log.actionValue {
        case .priorityUpdated: return "flag.fill"
        case .statusUpdated: return "arrow.triangle.2.circlepath"
        case .volunteerAssigned: return "person.badge.plus"
        }
    }

    private var color: Color {
        switch log.actionValue {
        case .priorityUpdated: return .orange
        case .statusUpdated: return .blue
        case .volunteerAssigned: return .green
        }
    }
}

private struct CoordinatorLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading coordinator dashboard...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

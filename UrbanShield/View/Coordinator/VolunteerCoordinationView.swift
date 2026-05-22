//
//  VolunteerCoordinationView.swift
//  UrbanShield
//

import SwiftUI

struct VolunteerCoordinationView: View {
    let sessionViewModel: AuthSessionViewModel

    @State private var viewModel = VolunteerCoordinationViewModel()
    @State private var selectedFilter: VolunteerCoordinationFilter = .all

    private var currentUser: User? {
        if case .authenticated(let user) = sessionViewModel.session {
            return user
        }
        return nil
    }

    private var filteredMembers: [VolunteerCoordinationMember] {
        viewModel.members.filter { selectedFilter.includes($0) }
    }

    var body: some View {
        ZStack {
            RequestUI.background
                .ignoresSafeArea()

            if viewModel.isLoading && viewModel.members.isEmpty {
                VolunteerCoordinationLoadingView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        header
                            .padding(.top, 8)

                        metricsGrid

                        filterBar

                        if filteredMembers.isEmpty {
                            emptyState
                        } else {
                            ForEach(filteredMembers) { member in
                                VolunteerCoordinationCard(
                                    member: member,
                                    sessionViewModel: sessionViewModel
                                )
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 18)
                }
                .refreshable {
                    await reloadVolunteers()
                }
            }
        }
        .navigationTitle("Volunteers")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await reloadVolunteers() }
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
            await reloadVolunteers()
        }
    }

    private func reloadVolunteers() async {
        await viewModel.loadVolunteers(currentUser: currentUser)
    }

    private var header: some View {
        RequestCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "person.2.badge.gearshape.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Volunteer Coordination")
                        .font(.title2.bold())

                    Text("Track available helpers, busy assignments, skills, and the active request each volunteer is handling.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            VolunteerCoordinationMetricCard(
                title: "Ready",
                value: "\(viewModel.skilledAvailableCount)",
                systemImage: "checkmark.shield.fill",
                color: .green
            )

            VolunteerCoordinationMetricCard(
                title: "Busy",
                value: "\(viewModel.busyCount)",
                systemImage: "figure.run",
                color: .orange
            )

            VolunteerCoordinationMetricCard(
                title: "Offline",
                value: "\(viewModel.offlineCount)",
                systemImage: "moon.zzz.fill",
                color: .gray
            )

            VolunteerCoordinationMetricCard(
                title: "Total",
                value: "\(viewModel.totalCount)",
                systemImage: "person.3.fill",
                color: .blue
            )
        }
    }

    private var filterBar: some View {
        Picker("Volunteer Filter", selection: $selectedFilter) {
            ForEach(VolunteerCoordinationFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Volunteers",
            systemImage: "person.2.slash",
            description: Text("No volunteers match the selected coordination filter.")
        )
        .padding(.vertical, 40)
    }
}

private enum VolunteerCoordinationFilter: String, CaseIterable, Identifiable {
    case all
    case available
    case busy
    case offline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .available: return "Ready"
        case .busy: return "Busy"
        case .offline: return "Offline"
        }
    }

    func includes(_ member: VolunteerCoordinationMember) -> Bool {
        switch self {
        case .all:
            return true
        case .available:
            return member.displayAvailability == .available
        case .busy:
            return member.displayAvailability == .busy
        case .offline:
            return member.displayAvailability == .offline
        }
    }
}

private struct VolunteerCoordinationMetricCard: View {
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

private struct VolunteerCoordinationCard: View {
    let member: VolunteerCoordinationMember
    let sessionViewModel: AuthSessionViewModel

    var body: some View {
        RequestCard {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(availabilityColor.opacity(0.14))

                    Image(systemName: availabilityIcon)
                        .font(.headline)
                        .foregroundStyle(availabilityColor)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 5) {
                    Text(member.profile.fullName)
                        .font(.headline)
                        .lineLimit(1)

                    Text(member.profile.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                availabilityChip
            }

            skillSection

            if let assignment = member.assignment {
                assignmentSection(assignment)
            } else {
                idleSection
            }
        }
    }

    private var skillSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            RequestSectionTitle(title: "Skills", systemImage: "wrench.and.screwdriver.fill")

            if member.profile.skillsValue.isEmpty {
                Text("No volunteer skills added yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(member.profile.skillsValue) { skill in
                        Text(skill.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func assignmentSection(_ assignment: HelpRequestVolunteerRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.subheadline)
                    .foregroundStyle(RequestUI.statusColor(assignment.statusValue))
                    .frame(width: 32, height: 32)
                    .background(RequestUI.statusColor(assignment.statusValue).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(member.activeRequest?.requestTypeValue.title ?? "Assigned Request")
                        .font(.subheadline.weight(.semibold))

                    Text("Accepted \(assignment.acceptedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                RequestStatusChip(status: assignment.statusValue)
            }

            if let request = member.activeRequest {
                HStack(spacing: 8) {
                    RequestUrgencyChip(urgency: request.urgencyValue)
                    Spacer()
                }

                NavigationLink {
                    RequestDetailView(
                        requestId: request.id,
                        sessionViewModel: sessionViewModel
                    )
                } label: {
                    Label("Open Request", systemImage: "arrow.up.right.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                }
                .buttonStyle(.bordered)
            } else {
                Text("Assignment exists, but the request could not be loaded. Check request read policies if this stays visible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var idleSection: some View {
        HStack(spacing: 10) {
            Image(systemName: member.displayAvailability == .available ? "scope" : "pause.circle.fill")
                .font(.subheadline)
                .foregroundStyle(availabilityColor)
                .frame(width: 32, height: 32)
                .background(availabilityColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(member.displayAvailability == .available ? "Ready for assignment" : "Not taking new work")
                    .font(.subheadline.weight(.semibold))

                Text(idleDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var availabilityChip: some View {
        Label(member.displayAvailability.title, systemImage: availabilityIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(availabilityColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(availabilityColor.opacity(0.12))
            .clipShape(Capsule())
    }

    private var idleDescription: String {
        switch member.displayAvailability {
        case .available:
            return member.profile.skillsValue.isEmpty ? "Add skills before this user can be matched." : "Available for matching from the request dashboard."
        case .busy:
            return "Marked busy without a loaded active assignment."
        case .offline:
            return "Offline volunteers are hidden from request assignment menus."
        }
    }

    private var availabilityIcon: String {
        switch member.displayAvailability {
        case .available: return "checkmark.circle.fill"
        case .busy: return "figure.run"
        case .offline: return "moon.zzz.fill"
        }
    }

    private var availabilityColor: Color {
        switch member.displayAvailability {
        case .available: return .green
        case .busy: return .orange
        case .offline: return .gray
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: width, height: currentY + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(size)
            )
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct VolunteerCoordinationLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading volunteer coordination...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

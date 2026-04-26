//
//  MyRequestsView.swift
//  UrbanShield
//

import SwiftUI

struct MyRequestsView: View {
    let sessionViewModel: AuthSessionViewModel

    @State private var viewModel = MyRequestsViewModel()
    @State private var selectedFilter: RequestListFilter = .all
    private let horizontalPadding: CGFloat = 16

    private var currentUser: User? {
        if case .authenticated(let user) = sessionViewModel.session {
            return user
        }
        return nil
    }

    private var filteredRequests: [HelpRequestRecord] {
        viewModel.requests.filter { selectedFilter.includes($0) }
    }

    var body: some View {
        ZStack {
            RequestUI.background
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.isLoading && viewModel.requests.isEmpty {
                        RequestLoadingView(title: "Loading requests...")
                            .frame(minHeight: 320)
                    } else if viewModel.requests.isEmpty {
                        emptyState
                    } else {
                        RequestSummaryBar(requests: viewModel.requests)
                            .padding(.horizontal, horizontalPadding)

                        RequestFilterBar(selection: $selectedFilter)
                            .padding(.bottom, 4)

                        if filteredRequests.isEmpty {
                            filteredEmptyState
                        } else {
                            ForEach(filteredRequests) { request in
                                NavigationLink {
                                    RequestDetailView(
                                        requestId: request.id,
                                        sessionViewModel: sessionViewModel
                                    )
                                } label: {
                                    RequestRowView(request: request)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, horizontalPadding)
                            }
                        }
                    }
                }
                .padding(.bottom, 18)
            }
            .refreshable {
                await reloadRequests()
            }
        }
        .navigationTitle("My Requests")
        .overlay(alignment: .bottom) {
            if let error = viewModel.errorMessage {
                RequestErrorBanner(message: error)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            NavigationLink {
                CreateRequestView(sessionViewModel: sessionViewModel)
            } label: {
                Image(systemName: "plus")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.blue)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create Request")
            .padding(.trailing, 20)
            .padding(.bottom, 12)
        }
        .task {
            await reloadRequests()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ContentUnavailableView(
                "No Requests",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Create your first help request and track it here.")
            )
        }
        .padding(24)
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 18) {
            ContentUnavailableView(
                "No \(selectedFilter.title) Requests",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Try a different filter or pull to refresh.")
            )

            Button {
                selectedFilter = .all
            } label: {
                Label("Show All Requests", systemImage: "tray.full.fill")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
    }

    private func reloadRequests() async {
        await viewModel.loadRequests(citizenId: currentUser?.id)
    }
}

private enum RequestListFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case completed
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .active: return "Active"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .active: return "bolt.fill"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    func includes(_ request: HelpRequestRecord) -> Bool {
        switch self {
        case .all:
            return true
        case .active:
            return request.statusValue.isActive
        case .completed:
            return request.statusValue == .completed
        case .cancelled:
            return request.statusValue == .cancelled
        }
    }
}

private struct RequestRowView: View {
    let request: HelpRequestRecord

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(RequestUI.statusColor(request.statusValue))
                .frame(width: 5)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: RequestUI.requestIcon(request.requestTypeValue))
                        .font(.headline)
                        .foregroundStyle(RequestUI.urgencyColor(request.urgencyValue))
                        .frame(width: 38, height: 38)
                        .background(RequestUI.urgencyColor(request.urgencyValue).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(request.requestTypeValue.title)
                            .font(.headline)

                        Text(request.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    RequestStatusChip(status: request.statusValue)
                }

                Text(request.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    RequestUrgencyChip(urgency: request.urgencyValue)

                    RequestMetaPill(
                        title: coordinateText,
                        systemImage: "location.fill"
                    )
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RequestUI.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }

    private var coordinateText: String {
        let latitude = request.latitude.formatted(.number.precision(.fractionLength(2...4)))
        let longitude = request.longitude.formatted(.number.precision(.fractionLength(2...4)))
        return "\(latitude), \(longitude)"
    }
}

private struct RequestSummaryBar: View {
    let requests: [HelpRequestRecord]

    private var openCount: Int {
        requests.filter { $0.statusValue.isActive }.count
    }

    private var criticalCount: Int {
        requests.filter { $0.urgencyValue == .critical }.count
    }

    var body: some View {
        HStack(spacing: 10) {
            SummaryPill(title: "Total", value: requests.count, systemImage: "tray.full.fill", color: .blue)
            SummaryPill(title: "Active", value: openCount, systemImage: "bolt.fill", color: .orange)
            SummaryPill(title: "Critical", value: criticalCount, systemImage: "exclamationmark.triangle.fill", color: .red)
        }
    }
}

private struct SummaryPill: View {
    let title: String
    let value: Int
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.headline)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 62)
        .background(RequestUI.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct RequestFilterBar: View {
    @Binding var selection: RequestListFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RequestListFilter.allCases) { filter in
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            selection = filter
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: filter.systemImage)
                                .font(.caption.weight(.semibold))

                            Text(filter.title)
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(selection == filter ? .white : .primary)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background {
                            Capsule()
                                .fill(selection == filter ? Color.accentColor : RequestUI.card)
                        }
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.primary.opacity(selection == filter ? 0 : 0.06))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(filter.title) requests")
                    .accessibilityValue(selection == filter ? "Selected" : "Not selected")
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 42)
    }
}

private struct RequestMetaPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(Capsule())
    }
}

private struct RequestLoadingView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

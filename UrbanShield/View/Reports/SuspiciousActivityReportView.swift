//
//  SuspiciousActivityReportView.swift
//  UrbanShield
//

import SwiftUI

struct SuspiciousActivityReportView: View {
    let sessionViewModel: AuthSessionViewModel

    @State private var viewModel = SuspiciousActivityReportViewModel()
    @State private var isRequestPickerPresented = false

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

            if viewModel.isLoading && viewModel.visibleRequests.isEmpty {
                ReportLoadingView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        header
                            .padding(.top, 8)

                        reportForm

                        myReports
                    }
                    .padding(16)
                    .padding(.bottom, 18)
                }
                .refreshable {
                    await reload()
                }
            }
        }
        .navigationTitle("Report Activity")
        .navigationBarTitleDisplayMode(.inline)
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
            } else if let success = viewModel.successMessage {
                RequestInfoBanner(message: success, color: .green)
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
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Suspicious Activity")
                        .font(.title2.bold())

                    Text("Report fake requests, abuse, spam, or unsafe behavior. Reports are sent to admin moderation.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var reportForm: some View {
            RequestCard {
                RequestSectionTitle(title: "New Report", systemImage: "flag.fill")

            ReportRequestSelectorButton(
                selectionTitle: viewModel.requestTitle(for: viewModel.selectedRequestId),
                selectedRequest: viewModel.selectedRequest,
                requestCount: viewModel.visibleRequests.count
            ) {
                isRequestPickerPresented = true
            }
            .sheet(isPresented: $isRequestPickerPresented) {
                ReportRequestPickerSheet(
                    requests: viewModel.visibleRequests,
                    selectedRequestId: viewModel.selectedRequestId
                ) { request in
                    viewModel.selectedRequestId = request?.id
                }
            }

            Picker("Category", selection: $viewModel.category) {
                ForEach(SuspiciousReportCategory.allCases) { category in
                    Text(category.title).tag(category)
                }
            }

            TextField("Describe what looked suspicious", text: $viewModel.details, axis: .vertical)
                .lineLimit(4...7)
                .textInputAutocapitalization(.sentences)
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            RequestPrimaryButton(
                title: "Send Report",
                systemImage: "paperplane.fill",
                isLoading: viewModel.isSubmitting
            ) {
                Task { await viewModel.submit(currentUser: currentUser) }
            }
        }
    }

    private var myReports: some View {
        RequestCard {
            RequestSectionTitle(title: "My Recent Reports", systemImage: "tray.full.fill")

            if viewModel.myReports.isEmpty {
                Label("No reports submitted yet.", systemImage: "flag")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(viewModel.myReports.prefix(8)) { report in
                    MySuspiciousReportRow(report: report, requestTitle: viewModel.requestTitle(for: report.requestId))
                    if report.id != viewModel.myReports.prefix(8).last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct ReportRequestSelectorButton: View {
    let selectionTitle: String
    let selectedRequest: HelpRequestRecord?
    let requestCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Linked Request")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(selectionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let selectedRequest {
                        Text(selectedRequest.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("\(requestCount) visible requests available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "magnifyingglass.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ReportRequestPickerSheet: View {
    let requests: [HelpRequestRecord]
    let selectedRequestId: UUID?
    let onSelect: (HelpRequestRecord?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredRequests: [HelpRequestRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return requests }

        return requests.filter { request in
            [
                request.id.uuidString,
                request.requestTypeValue.title,
                request.statusValue.title,
                request.urgencyValue.title,
                request.description,
                request.createdAt.formatted(date: .abbreviated, time: .shortened),
                String(format: "%.4f %.4f", request.latitude, request.longitude)
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RequestUI.background
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 12) {
                        noLinkedRequestButton

                        if filteredRequests.isEmpty {
                            ContentUnavailableView(
                                "No Matching Requests",
                                systemImage: "magnifyingglass",
                                description: Text("Search by type, status, urgency, description, date, location, or request ID.")
                            )
                            .padding(.vertical, 32)
                        } else {
                            ForEach(filteredRequests) { request in
                                Button {
                                    onSelect(request)
                                    dismiss()
                                } label: {
                                    ReportRequestPickerCard(
                                        request: request,
                                        isSelected: request.id == selectedRequestId
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 18)
                }
            }
            .navigationTitle("Select Request")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search request details")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var noLinkedRequestButton: some View {
        Button {
            onSelect(nil)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selectedRequestId == nil ? "checkmark.circle.fill" : "link.badge.plus")
                    .font(.title3)
                    .foregroundStyle(selectedRequestId == nil ? .green : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text("No Linked Request")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Use this when the report is about general abuse or unsafe behavior.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(14)
            .background(RequestUI.card)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ReportRequestPickerCard: View {
    let request: HelpRequestRecord
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: RequestUI.requestIcon(request.requestTypeValue))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(statusColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(request.requestTypeValue.title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("#\(request.id.uuidString.prefix(8))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(Capsule())
                    }

                    Text(request.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                }
            }

            Text(request.description)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ReportRequestChip(
                        title: request.statusValue.title,
                        systemImage: "waveform.path.ecg",
                        color: statusColor
                    )

                    ReportRequestChip(
                        title: request.urgencyValue.title,
                        systemImage: "exclamationmark.triangle.fill",
                        color: urgencyColor
                    )
                }

                ReportRequestChip(
                    title: String(format: "%.4f, %.4f", request.latitude, request.longitude),
                    systemImage: "location.fill",
                    color: .gray
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RequestUI.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.green : Color.clear, lineWidth: 2)
        }
    }

    private var statusColor: Color {
        switch request.statusValue {
        case .open: return .blue
        case .confirmed: return .orange
        case .inProgress: return .purple
        case .completed: return .green
        case .cancelled: return .red
        }
    }

    private var urgencyColor: Color {
        switch request.urgencyValue {
        case .low: return .green
        case .medium: return .blue
        case .high: return .orange
        case .critical: return .red
        }
    }
}

private struct ReportRequestChip: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct MySuspiciousReportRow: View {
    let report: SuspiciousActivityReportRecord
    let requestTitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.subheadline)
                .foregroundStyle(statusColor)
                .frame(width: 32, height: 32)
                .background(statusColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

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
                .foregroundStyle(statusColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(statusColor.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        switch report.statusValue {
        case .open: return .red
        case .reviewing: return .orange
        case .resolved: return .green
        case .dismissed: return .gray
        }
    }
}

private struct ReportLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading report form...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

//
//  RequestDetailView.swift
//  UrbanShield
//

import PhotosUI
import SwiftUI

struct RequestDetailView: View {
    let requestId: UUID
    let sessionViewModel: AuthSessionViewModel

    @State private var viewModel = RequestDetailViewModel()
    @State private var showCancelConfirmation = false
    @State private var showEditSheet = false
    @State private var selectedEvidenceItem: PhotosPickerItem?

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

            if viewModel.isLoading && viewModel.request == nil {
                DetailLoadingView()
            } else if let request = viewModel.request {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        detailHeader(request)

                        RequestCard {
                            RequestSectionTitle(title: "Status", systemImage: "checklist")

                            HStack(spacing: 10) {
                                RequestStatusChip(status: request.statusValue)
                                RequestPriorityChip(priority: request.priorityValue)
                                RequestUrgencyChip(urgency: request.urgencyValue)
                            }

                            RequestProgressView(status: request.statusValue)
                        }

                        RequestCard {
                            RequestSectionTitle(title: "Description", systemImage: "text.alignleft")

                            Text(request.description)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        evidenceSection(request)

                        RequestCard {
                            RequestSectionTitle(title: "Location", systemImage: "location.fill")

                            HStack(spacing: 10) {
                                DetailMetric(
                                    title: "Latitude",
                                    value: coordinateText(request.latitude)
                                )
                                DetailMetric(
                                    title: "Longitude",
                                    value: coordinateText(request.longitude)
                                )
                            }
                        }

                        RequestCard {
                            RequestSectionTitle(title: "Timeline", systemImage: "clock.fill")

                            DetailRow(
                                title: "Created",
                                value: request.createdAt.formatted(date: .abbreviated, time: .shortened)
                            )
                            Divider()
                            DetailRow(
                                title: "Updated",
                                value: request.updatedAt.formatted(date: .abbreviated, time: .shortened)
                            )
                        }
                    }
                    .padding(16)
                    .padding(.bottom, bottomActionPadding(for: request))
                }
                .refreshable {
                    await reloadRequest()
                }
            } else {
                ContentUnavailableView(
                    "Request Not Found",
                    systemImage: "questionmark.folder",
                    description: Text("The selected help request could not be loaded.")
                )
            }
        }
        .navigationTitle("Request Detail")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let request = viewModel.request, shouldShowCitizenControls(for: request) {
                VStack(spacing: 10) {
                    Button {
                        viewModel.prepareEditForm()
                        showEditSheet = true
                    } label: {
                        Label("Update Request", systemImage: "square.and.pencil")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isSavingUpdate || viewModel.isCancelling)

                    Button(role: .destructive) {
                        showCancelConfirmation = true
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isCancelling {
                                ProgressView()
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                Text("Cancel Request")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isCancelling || viewModel.isSavingUpdate)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(.regularMaterial)
            } else if let request = viewModel.request, shouldShowVolunteerAction(for: request) {
                VStack(spacing: 10) {
                    Button {
                        Task {
                            if request.statusValue == .confirmed {
                                await viewModel.startVolunteerWork(id: requestId, currentUser: currentUser)
                            } else {
                                await viewModel.completeVolunteerWork(id: requestId, currentUser: currentUser)
                                await sessionViewModel.refreshCurrentUser()
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isUpdatingStatus {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: volunteerActionIcon(for: request))
                                Text(volunteerActionTitle(for: request))
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isUpdatingStatus)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                .background(.regularMaterial)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await reloadRequest()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading || viewModel.isCancelling)
            }
        }
        .overlay(alignment: .bottom) {
            if let error = viewModel.errorMessage {
                RequestErrorBanner(message: error)
            } else if let success = viewModel.successMessage {
                RequestInfoBanner(message: success, color: .green)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditRequestSheet(viewModel: viewModel) {
                Task {
                    let didUpdate = await viewModel.updateRequest(id: requestId, currentUser: currentUser)
                    if didUpdate {
                        showEditSheet = false
                    }
                }
            }
        }
        .confirmationDialog(
            "Cancel this request?",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel Request", role: .destructive) {
                Task {
                    await viewModel.cancelRequest(id: requestId, currentUser: currentUser)
                    await sessionViewModel.refreshCurrentUser()
                }
            }
            Button("Keep Request", role: .cancel) {}
        } message: {
            Text("This will mark your request as cancelled.")
        }
        .task {
            await reloadRequest()
        }
        .onChange(of: selectedEvidenceItem) { _, newItem in
            uploadSelectedEvidence(newItem)
        }
    }

    private func reloadRequest() async {
        await viewModel.loadRequest(id: requestId, currentUserId: currentUser?.id)
        await sessionViewModel.refreshCurrentUser()
    }

    private func detailHeader(_ request: HelpRequestRecord) -> some View {
        HStack(spacing: 14) {
            Image(systemName: RequestUI.requestIcon(request.requestTypeValue))
                .font(.title2)
                .foregroundStyle(RequestUI.urgencyColor(request.urgencyValue))
                .frame(width: 46, height: 46)
                .background(RequestUI.urgencyColor(request.urgencyValue).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(request.requestTypeValue.title)
                    .font(.title2.bold())
                Text("Request ID \(request.id.uuidString.prefix(8))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func coordinateText(_ coordinate: Double) -> String {
        coordinate.formatted(.number.precision(.fractionLength(4...6)))
    }

    private func shouldShowCitizenCancel(for request: HelpRequestRecord) -> Bool {
        request.citizenId == currentUser?.id && request.statusValue.canBeCancelled
    }

    private func shouldShowCitizenControls(for request: HelpRequestRecord) -> Bool {
        request.citizenId == currentUser?.id
            && request.statusValue != .completed
            && request.statusValue != .cancelled
    }

    private func shouldShowEvidenceUpload(for request: HelpRequestRecord) -> Bool {
        let isRequestOwner = request.citizenId == currentUser?.id
        let isAssignedVolunteer = request.volunteerId == currentUser?.id

        return (isRequestOwner || isAssignedVolunteer)
            && request.statusValue != .completed
            && request.statusValue != .cancelled
    }

    private func shouldShowVolunteerAction(for request: HelpRequestRecord) -> Bool {
        request.volunteerId == currentUser?.id
            && (request.statusValue == .confirmed || request.statusValue == .inProgress)
    }

    private func bottomActionPadding(for request: HelpRequestRecord) -> CGFloat {
        shouldShowCitizenControls(for: request) ? 148 : (shouldShowVolunteerAction(for: request) ? 86 : 16)
    }

    private func volunteerActionTitle(for request: HelpRequestRecord) -> String {
        request.statusValue == .confirmed ? "Start Response" : "Mark Completed"
    }

    private func volunteerActionIcon(for request: HelpRequestRecord) -> String {
        request.statusValue == .confirmed ? "play.fill" : "checkmark.circle.fill"
    }

    private func evidenceSection(_ request: HelpRequestRecord) -> some View {
        RequestCard {
            HStack(alignment: .firstTextBaseline) {
                RequestSectionTitle(title: "Evidence", systemImage: "photo.on.rectangle.angled")
                Spacer()

                if shouldShowEvidenceUpload(for: request) {
                    PhotosPicker(
                        selection: $selectedEvidenceItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        if viewModel.isUploadingEvidence {
                            ProgressView()
                        } else {
                            Label("Add Photo", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isUploadingEvidence || !viewModel.canUploadMoreEvidence)
                }
            }

            if viewModel.evidenceItems.isEmpty {
                Label("No evidence photos uploaded yet.", systemImage: "photo")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.evidenceItems) { item in
                        EvidenceRow(item: item)
                    }
                }
            }

            if shouldShowEvidenceUpload(for: request), !viewModel.canUploadMoreEvidence {
                Label("Evidence upload limit reached for this request.", systemImage: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func uploadSelectedEvidence(_ item: PhotosPickerItem?) {
        guard let item else { return }

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    viewModel.errorMessage = "Selected photo could not be loaded."
                    selectedEvidenceItem = nil
                    return
                }

                await viewModel.uploadEvidence(
                    imageData: data,
                    originalFileName: "evidence.jpg",
                    currentUser: currentUser
                )
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }

            selectedEvidenceItem = nil
        }
    }
}

private struct EditRequestSheet: View {
    @Bindable var viewModel: RequestDetailViewModel
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field {
        case description
        case latitude
        case longitude
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RequestCard {
                        RequestSectionTitle(title: "Situation Details", systemImage: "text.alignleft")

                        TextEditor(text: $viewModel.editDescription)
                            .focused($focusedField, equals: .description)
                            .frame(minHeight: 140)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    RequestCard {
                        RequestSectionTitle(title: "Urgency", systemImage: "gauge.with.needle")

                        Picker("Urgency", selection: $viewModel.editUrgency) {
                            ForEach(HelpRequestUrgency.allCases) { urgency in
                                Text(urgency.title).tag(urgency)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    RequestCard {
                        RequestSectionTitle(title: "Location", systemImage: "location.fill")

                        VStack(spacing: 12) {
                            EditCoordinateField(
                                title: "Latitude",
                                text: $viewModel.editLatitude,
                                focusedField: $focusedField,
                                field: .latitude
                            )

                            EditCoordinateField(
                                title: "Longitude",
                                text: $viewModel.editLongitude,
                                focusedField: $focusedField,
                                field: .longitude
                            )
                        }
                    }
                }
                .padding(16)
            }
            .background(RequestUI.background)
            .navigationTitle("Update Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        focusedField = nil
                        onSave()
                    } label: {
                        if viewModel.isSavingUpdate {
                            ProgressView()
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(viewModel.isSavingUpdate)
                }
            }
        }
        .presentationDetents([.large])
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct EditCoordinateField<Field: Hashable>: View {
    let title: String
    @Binding var text: String
    let focusedField: FocusState<Field?>.Binding
    let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField(title, text: $text)
                .focused(focusedField, equals: field)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct EvidenceRow: View {
    let item: RequestEvidenceViewState

    var body: some View {
        HStack(spacing: 12) {
            EvidenceThumbnail(url: item.signedURL)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.record.fileName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(item.record.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(ByteCountFormatter.string(fromByteCount: Int64(item.record.fileSize), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct EvidenceThumbnail: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    @unknown default:
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 64)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct DetailMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct RequestProgressView: View {
    let status: HelpRequestStatus

    private let flow: [HelpRequestStatus] = [.open, .confirmed, .inProgress, .completed]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Request Flow")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(Array(flow.enumerated()), id: \.element.id) { index, step in
                    ProgressStep(
                        status: step,
                        isReached: isReached(step),
                        isCurrent: status == step
                    )

                    if index < flow.count - 1 {
                        Rectangle()
                            .fill(lineColor(after: step))
                            .frame(height: 2)
                    }
                }
            }

            if status == .cancelled {
                Label("This request was cancelled before completion.", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func isReached(_ step: HelpRequestStatus) -> Bool {
        guard status != .cancelled,
              let currentIndex = flow.firstIndex(of: status),
              let stepIndex = flow.firstIndex(of: step) else {
            return false
        }
        return stepIndex <= currentIndex
    }

    private func lineColor(after step: HelpRequestStatus) -> Color {
        guard status != .cancelled,
              let currentIndex = flow.firstIndex(of: status),
              let stepIndex = flow.firstIndex(of: step) else {
            return Color(.separator)
        }
        return stepIndex < currentIndex ? RequestUI.statusColor(status) : Color(.separator)
    }
}

private struct ProgressStep: View {
    let status: HelpRequestStatus
    let isReached: Bool
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: isReached ? "checkmark.circle.fill" : "circle")
                .font(.headline)
                .foregroundStyle(isReached ? RequestUI.statusColor(status) : .secondary)

            Text(status.shortTitle)
                .font(.caption2.weight(isCurrent ? .bold : .regular))
                .foregroundStyle(isCurrent ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(width: 54)
    }
}

private struct DetailLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading request...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

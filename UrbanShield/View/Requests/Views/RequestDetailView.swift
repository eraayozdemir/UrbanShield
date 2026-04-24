//
//  RequestDetailView.swift
//  UrbanShield
//

import SwiftUI

struct RequestDetailView: View {
    let requestId: UUID
    let sessionViewModel: AuthSessionViewModel

    @State private var viewModel = RequestDetailViewModel()
    @State private var showCancelConfirmation = false

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
                                RequestUrgencyChip(urgency: request.urgencyValue)
                            }
                        }

                        RequestCard {
                            RequestSectionTitle(title: "Description", systemImage: "text.alignleft")

                            Text(request.description)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

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
                    .padding(.bottom, request.statusValue.canBeCancelled ? 86 : 16)
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
            if viewModel.request?.statusValue.canBeCancelled == true {
                VStack(spacing: 10) {
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
                    .disabled(viewModel.isCancelling)
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
                        await viewModel.loadRequest(id: requestId)
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
            }
        }
        .confirmationDialog(
            "Cancel this request?",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel Request", role: .destructive) {
                Task {
                    await viewModel.cancelRequest(id: requestId, citizenId: currentUser?.id)
                }
            }
            Button("Keep Request", role: .cancel) {}
        } message: {
            Text("This will mark your request as cancelled.")
        }
        .task {
            await viewModel.loadRequest(id: requestId)
        }
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

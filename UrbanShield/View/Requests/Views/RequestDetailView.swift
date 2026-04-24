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
        Group {
            if viewModel.isLoading && viewModel.request == nil {
                ProgressView("Loading request...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let request = viewModel.request {
                Form {
                    Section("Status") {
                        DetailRow(title: "Current Status", value: request.statusValue.title)
                        DetailRow(title: "Urgency", value: request.urgencyValue.title)
                    }

                    Section("Request") {
                        DetailRow(title: "Type", value: request.requestTypeValue.title)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(request.description)
                        }
                    }

                    Section("Location") {
                        DetailRow(title: "Latitude", value: String(request.latitude))
                        DetailRow(title: "Longitude", value: String(request.longitude))
                    }

                    Section("Dates") {
                        DetailRow(
                            title: "Created",
                            value: request.createdAt.formatted(date: .abbreviated, time: .shortened)
                        )
                        DetailRow(
                            title: "Updated",
                            value: request.updatedAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    }

                    if request.statusValue.canBeCancelled {
                        Section {
                            Button(role: .destructive) {
                                showCancelConfirmation = true
                            } label: {
                                HStack {
                                    Spacer()
                                    if viewModel.isCancelling {
                                        ProgressView()
                                    } else {
                                        Text("Cancel Request")
                                            .fontWeight(.semibold)
                                    }
                                    Spacer()
                                }
                            }
                            .disabled(viewModel.isCancelling)
                        }
                    }
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
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.red)
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

//
//  MyRequestsView.swift
//  UrbanShield
//

import SwiftUI

struct MyRequestsView: View {
    let sessionViewModel: AuthSessionViewModel

    @State private var viewModel = MyRequestsViewModel()

    private var currentUser: User? {
        if case .authenticated(let user) = sessionViewModel.session {
            return user
        }
        return nil
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.requests.isEmpty {
                ProgressView("Loading requests...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.requests.isEmpty {
                ContentUnavailableView(
                    "No Requests",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Submitted help requests will appear here.")
                )
            } else {
                List(viewModel.requests) { request in
                    NavigationLink {
                        RequestDetailView(
                            requestId: request.id,
                            sessionViewModel: sessionViewModel
                        )
                    } label: {
                        RequestRowView(request: request)
                    }
                }
                .refreshable {
                    await viewModel.loadRequests(citizenId: currentUser?.id)
                }
            }
        }
        .navigationTitle("My Requests")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.loadRequests(citizenId: currentUser?.id)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
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
        .task {
            await viewModel.loadRequests(citizenId: currentUser?.id)
        }
    }
}

private struct RequestRowView: View {
    let request: HelpRequestRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(request.requestTypeValue.title)
                    .font(.headline)

                Spacer()

                Text(request.statusValue.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            HStack(spacing: 12) {
                Label(request.urgencyValue.title, systemImage: "exclamationmark.triangle")
                Label(request.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch request.statusValue {
        case .open: return .blue
        case .inProgress: return .orange
        case .completed: return .green
        case .cancelled: return .red
        }
    }
}

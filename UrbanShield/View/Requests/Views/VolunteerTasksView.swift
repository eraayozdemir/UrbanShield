//
//  VolunteerTasksView.swift
//  UrbanShield
//

import SwiftUI

struct VolunteerTasksView: View {
    let sessionViewModel: AuthSessionViewModel

    @State private var viewModel = VolunteerTasksViewModel()

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

            if viewModel.isLoading && viewModel.tasks.isEmpty {
                VolunteerLoadingView(title: "Loading volunteer tasks...")
            } else if viewModel.tasks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        volunteerHeader
                            .padding(.top, 8)

                        ForEach(viewModel.tasks) { task in
                            NavigationLink {
                                RequestDetailView(
                                    requestId: task.id,
                                    sessionViewModel: sessionViewModel
                                )
                            } label: {
                                VolunteerTaskCard(task: task)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 18)
                }
                .refreshable {
                    await viewModel.loadTasks(volunteerId: currentUser?.id)
                }
            }
        }
        .navigationTitle("Volunteer Tasks")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.loadTasks(volunteerId: currentUser?.id)
                    }
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
            await viewModel.loadTasks(volunteerId: currentUser?.id)
        }
    }

    private var volunteerHeader: some View {
        RequestCard {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Assigned response work")
                        .font(.title3.bold())

                    Text("Start confirmed requests, then complete them when action is finished.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ContentUnavailableView(
                "No Volunteer Tasks",
                systemImage: "checkmark.shield",
                description: Text("Confirm an open request from Nearby Requests to start volunteering.")
            )

            NavigationLink {
                NearbyRequestsView(sessionViewModel: sessionViewModel)
            } label: {
                Label("Find Nearby Requests", systemImage: "mappin.and.ellipse")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}

private struct VolunteerTaskCard: View {
    let task: HelpRequestRecord

    var body: some View {
        RequestCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: RequestUI.requestIcon(task.requestTypeValue))
                    .font(.headline)
                    .foregroundStyle(RequestUI.statusColor(task.statusValue))
                    .frame(width: 42, height: 42)
                    .background(RequestUI.statusColor(task.statusValue).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(task.requestTypeValue.title)
                        .font(.headline)

                    Text(task.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                RequestStatusChip(status: task.statusValue)
            }

            Text(task.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                RequestUrgencyChip(urgency: task.urgencyValue)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct VolunteerLoadingView: View {
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

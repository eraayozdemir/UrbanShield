//
//  NotificationsView.swift
//  UrbanShield
//

import SwiftUI

struct NotificationsView: View {
    let sessionViewModel: AuthSessionViewModel
    @State private var viewModel: NotificationsViewModel

    @MainActor
    init(
        sessionViewModel: AuthSessionViewModel,
        viewModel: NotificationsViewModel? = nil
    ) {
        self.sessionViewModel = sessionViewModel
        _viewModel = State(initialValue: viewModel ?? NotificationsViewModel())
    }

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

            if viewModel.isLoading && viewModel.notifications.isEmpty {
                ProgressView("Loading notifications...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.notifications.isEmpty {
                ContentUnavailableView(
                    "No Notifications",
                    systemImage: "bell.slash",
                    description: Text("Request updates, announcements, and moderation activity will appear here.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        unreadSummary

                        ForEach(viewModel.notifications) { notification in
                            notificationRow(notification)
                        }
                    }
                    .padding(16)
                }
                .refreshable {
                    await viewModel.load(currentUser: currentUser)
                }
            }
        }
        .navigationTitle("Notifications")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.markAllAsRead(currentUser: currentUser) }
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .disabled(viewModel.unreadCount == 0)
            }
        }
        .overlay(alignment: .bottom) {
            if let message = viewModel.errorMessage {
                RequestErrorBanner(message: message)
            } else if let message = viewModel.successMessage {
                RequestInfoBanner(message: message, color: .green)
            }
        }
        .task {
            await viewModel.load(currentUser: currentUser)
            await viewModel.startRealtime(currentUser: currentUser)
            viewModel.startPollingFallback(currentUser: currentUser)
        }
        .onDisappear {
            viewModel.stopRealtime()
        }
    }

    private var unreadSummary: some View {
        RequestCard {
            HStack(spacing: 14) {
                Image(systemName: viewModel.unreadCount == 0 ? "bell.badge" : "bell.badge.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(viewModel.unreadCount == 0 ? Color.secondary : Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(viewModel.unreadCount) unread")
                        .font(.headline)

                    Text("Important request, report, and announcement updates are collected here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func notificationRow(_ notification: InAppNotificationRecord) -> some View {
        if notification.linkTypeValue != nil {
            NavigationLink {
                notificationDestination(notification)
                    .task {
                        await viewModel.markAsRead(notification, currentUser: currentUser)
                    }
            } label: {
                NotificationRow(notification: notification)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                Task { await viewModel.markAsRead(notification, currentUser: currentUser) }
            } label: {
                NotificationRow(notification: notification)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func notificationDestination(_ notification: InAppNotificationRecord) -> some View {
        switch notification.linkTypeValue {
        case .request:
            if let requestId = notification.requestId ?? notification.linkId {
                RequestDetailView(requestId: requestId, sessionViewModel: sessionViewModel)
            } else {
                fallbackDetail(notification)
            }
        case .announcement:
            EmergencyAnnouncementsView(sessionViewModel: sessionViewModel)
        case .report:
            if currentUser?.role == .admin {
                AdminModerationView(sessionViewModel: sessionViewModel)
            } else {
                SuspiciousActivityReportView(sessionViewModel: sessionViewModel)
            }
        case .none:
            fallbackDetail(notification)
        }
    }

    private func fallbackDetail(_ notification: InAppNotificationRecord) -> some View {
        ScrollView {
            RequestCard {
                NotificationRow(notification: notification)

                Divider()

                Text(notification.message)
                    .font(.body)
            }
            .padding(16)
        }
        .background(RequestUI.background)
        .navigationTitle("Notification")
    }
}

private struct NotificationRow: View {
    let notification: InAppNotificationRecord

    var body: some View {
        RequestCard {
            HStack(alignment: .top, spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(color)
                        .frame(width: 46, height: 46)
                        .background(color.opacity(0.13))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    if !notification.isRead {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 10, height: 10)
                            .offset(x: 2, y: -2)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(notification.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Spacer(minLength: 8)

                        Text(relativeDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(notification.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    Text(categoryTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(color.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var icon: String {
        switch notification.categoryValue {
        case .request: return "exclamationmark.bubble.fill"
        case .assignment: return "checkmark.shield.fill"
        case .announcement: return "megaphone.fill"
        case .report: return "flag.fill"
        case .moderation: return "shield.lefthalf.filled.badge.checkmark"
        case .coordinator: return "person.2.badge.gearshape.fill"
        }
    }

    private var color: Color {
        switch notification.categoryValue {
        case .request: return .blue
        case .assignment: return .green
        case .announcement: return .orange
        case .report: return .red
        case .moderation: return .purple
        case .coordinator: return .indigo
        }
    }

    private var categoryTitle: String {
        switch notification.categoryValue {
        case .request: return "Request"
        case .assignment: return "Assignment"
        case .announcement: return "Announcement"
        case .report: return "Report"
        case .moderation: return "Moderation"
        case .coordinator: return "Coordinator"
        }
    }

    private var relativeDate: String {
        notification.createdAt.formatted(.relative(presentation: .named))
    }
}

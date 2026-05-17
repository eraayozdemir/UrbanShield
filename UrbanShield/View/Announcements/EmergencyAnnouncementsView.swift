//
//  EmergencyAnnouncementsView.swift
//  UrbanShield
//

import SwiftUI

struct EmergencyAnnouncementsView: View {
    let sessionViewModel: AuthSessionViewModel

    @State private var viewModel = EmergencyAnnouncementsViewModel()

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

            if viewModel.isLoading && viewModel.announcements.isEmpty {
                AnnouncementsLoadingView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        header
                            .padding(.top, 8)

                        if let latest = viewModel.latestAnnouncement {
                            LatestAnnouncementCard(announcement: latest)
                        }

                        if viewModel.announcements.isEmpty {
                            ContentUnavailableView(
                                "No Announcements",
                                systemImage: "megaphone",
                                description: Text("There are no active emergency announcements for your role.")
                            )
                            .padding(.vertical, 40)
                        } else {
                            ForEach(viewModel.announcements) { announcement in
                                EmergencyAnnouncementCard(announcement: announcement)
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 18)
                }
                .refreshable {
                    await reload()
                }
            }
        }
        .navigationTitle("Announcements")
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
                Image(systemName: "megaphone.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Emergency Announcements")
                        .font(.title2.bold())

                    Text("Read active warnings and instructions published by coordinators.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct LatestAnnouncementCard: View {
    let announcement: EmergencyAnnouncementRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(severityColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Latest Alert")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(announcement.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
            }

            Text(announcement.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(severityColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(severityColor.opacity(0.25), lineWidth: 1)
        }
    }

    private var severityColor: Color {
        AnnouncementStyle.color(for: announcement.severityValue)
    }
}

private struct EmergencyAnnouncementCard: View {
    let announcement: EmergencyAnnouncementRecord

    var body: some View {
        RequestCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: AnnouncementStyle.icon(for: announcement.severityValue))
                    .font(.headline)
                    .foregroundStyle(severityColor)
                    .frame(width: 38, height: 38)
                    .background(severityColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(announcement.title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Spacer()

                        Text(announcement.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(announcement.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        AnnouncementChip(
                            title: announcement.severityValue.title,
                            systemImage: "exclamationmark.triangle.fill",
                            color: severityColor
                        )

                        AnnouncementChip(
                            title: announcement.audienceValue.title,
                            systemImage: "person.2.fill",
                            color: .blue
                        )
                    }
                }
            }
        }
    }

    private var severityColor: Color {
        AnnouncementStyle.color(for: announcement.severityValue)
    }
}

private struct AnnouncementChip: View {
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

private enum AnnouncementStyle {
    static func color(for severity: EmergencyAnnouncementSeverity) -> Color {
        switch severity {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }

    static func icon(for severity: EmergencyAnnouncementSeverity) -> String {
        switch severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }
}

private struct AnnouncementsLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading announcements...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

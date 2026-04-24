//
//  VolunteerHomeView.swift
//  UrbanShield
//

import SwiftUI

struct VolunteerHomeView: View {
    let sessionViewModel: AuthSessionViewModel

    @State private var selectedTab: VolunteerTab = .tasks

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                VolunteerDashboardView(sessionViewModel: sessionViewModel)
            }
            .tabItem {
                Label(VolunteerTab.tasks.title, systemImage: VolunteerTab.tasks.systemImage)
            }
            .tag(VolunteerTab.tasks)

            NavigationStack {
                NearbyRequestsView(sessionViewModel: sessionViewModel)
            }
            .tabItem {
                Label(VolunteerTab.nearby.title, systemImage: VolunteerTab.nearby.systemImage)
            }
            .tag(VolunteerTab.nearby)

            NavigationStack {
                MyRequestsView(sessionViewModel: sessionViewModel)
            }
            .tabItem {
                Label(VolunteerTab.requests.title, systemImage: VolunteerTab.requests.systemImage)
            }
            .tag(VolunteerTab.requests)

            NavigationStack {
                ProfileView(sessionViewModel: sessionViewModel)
            }
            .tabItem {
                Label(VolunteerTab.profile.title, systemImage: VolunteerTab.profile.systemImage)
            }
            .tag(VolunteerTab.profile)
        }
        .tint(.green)
    }
}

private enum VolunteerTab: Hashable {
    case tasks
    case nearby
    case requests
    case profile

    var title: String {
        switch self {
        case .tasks: return "Tasks"
        case .nearby: return "Nearby"
        case .requests: return "Requests"
        case .profile: return "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .tasks: return "checkmark.shield.fill"
        case .nearby: return "mappin.and.ellipse"
        case .requests: return "list.bullet.rectangle.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }
}

private struct VolunteerDashboardView: View {
    let sessionViewModel: AuthSessionViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                NavigationLink {
                    VolunteerTasksView(sessionViewModel: sessionViewModel)
                } label: {
                    VolunteerActionRow(
                        icon: "checkmark.shield.fill",
                        title: "My Volunteer Tasks",
                        subtitle: "Continue confirmed requests and mark completed work.",
                        tint: .green
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    NearbyRequestsView(sessionViewModel: sessionViewModel)
                } label: {
                    VolunteerActionRow(
                        icon: "mappin.and.ellipse",
                        title: "Find Nearby Requests",
                        subtitle: "Confirm open requests from citizens in your area.",
                        tint: .blue
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    CreateRequestView(sessionViewModel: sessionViewModel)
                } label: {
                    VolunteerActionRow(
                        icon: "plus.circle.fill",
                        title: "Create Personal Request",
                        subtitle: "You can still act as a citizen when you need help.",
                        tint: .red
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .background(RequestUI.background)
        .navigationTitle("Volunteer")
    }

    private var header: some View {
        RequestCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "hands.sparkles.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Volunteer Mode")
                        .font(.title2.bold())

                    Text("You became a volunteer by confirming a citizen request. You can still create and track your own citizen requests.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct VolunteerActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(tint)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RequestUI.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

//
//  CitizenHomeView.swift
//  UrbanShield
//

import SwiftUI

struct CitizenHomeView: View {
    let sessionViewModel: AuthSessionViewModel

    @State private var selectedTab: CitizenTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                CitizenDashboardView(sessionViewModel: sessionViewModel)
            }
            .tabItem {
                Label(CitizenTab.home.title, systemImage: CitizenTab.home.systemImage)
            }
            .tag(CitizenTab.home)

            NavigationStack {
                MyRequestsView(sessionViewModel: sessionViewModel)
            }
            .tabItem {
                Label(CitizenTab.requests.title, systemImage: CitizenTab.requests.systemImage)
            }
            .tag(CitizenTab.requests)

            NavigationStack {
                ProfileView(sessionViewModel: sessionViewModel)
            }
            .tabItem {
                Label(CitizenTab.profile.title, systemImage: CitizenTab.profile.systemImage)
            }
            .tag(CitizenTab.profile)
        }
        .tint(.blue)
    }
}

private enum CitizenTab: Hashable {
    case home
    case requests
    case profile

    var title: String {
        switch self {
        case .home: return "Home"
        case .requests: return "Requests"
        case .profile: return "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "shield.lefthalf.filled"
        case .requests: return "list.bullet.rectangle.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }
}

private struct CitizenDashboardView: View {
    let sessionViewModel: AuthSessionViewModel

    private var currentUser: User? {
        if case .authenticated(let user) = sessionViewModel.session {
            return user
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                EmergencyActionPanel(sessionViewModel: sessionViewModel)

                NavigationLink {
                    MyRequestsView(sessionViewModel: sessionViewModel)
                } label: {
                    HomeActionRow(
                        icon: "list.bullet.rectangle.fill",
                        title: "My Requests",
                        subtitle: "View and manage your submitted requests.",
                        tint: .blue
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ProfileView(sessionViewModel: sessionViewModel)
                } label: {
                    HomeActionRow(
                        icon: "person.text.rectangle.fill",
                        title: "Profile",
                        subtitle: "Review your account and role information.",
                        tint: .teal
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .background(RequestUI.background)
        .navigationTitle("UrbanShield")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title)
                    .foregroundStyle(.blue)
                    .frame(width: 48, height: 48)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Citizen Hub")
                        .font(.title2.bold())

                    if let name = currentUser?.fullName {
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            Text("Create urgent reports, track your active requests, and keep your account ready for response coordination.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RequestUI.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct EmergencyActionPanel: View {
    let sessionViewModel: AuthSessionViewModel

    var body: some View {
        NavigationLink {
            CreateRequestView(sessionViewModel: sessionViewModel)
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Need help now?")
                            .font(.title3.bold())
                            .foregroundStyle(.white)

                        Text("Create a request with type, urgency, description, and manual coordinates.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Image(systemName: "plus")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.red)
                        .frame(width: 42, height: 42)
                        .background(.white)
                        .clipShape(Circle())
                }

                Label("Create Help Request", systemImage: "paperplane.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background(.white.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.red, .orange],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct HomeActionRow: View {
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

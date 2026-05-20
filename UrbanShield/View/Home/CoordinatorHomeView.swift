//
//  CoordinatorHomeView.swift
//  UrbanShield
//

import SwiftUI

struct CoordinatorHomeView: View {
    let sessionViewModel: AuthSessionViewModel

    @State private var selectedTab: CoordinatorTab = .requests

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                CoordinatorDashboardView(sessionViewModel: sessionViewModel)
            }
            .tabItem {
                Label(CoordinatorTab.requests.title, systemImage: CoordinatorTab.requests.systemImage)
            }
            .tag(CoordinatorTab.requests)

            NavigationStack {
                CoordinatorMapView(sessionViewModel: sessionViewModel)
            }
            .tabItem {
                Label(CoordinatorTab.map.title, systemImage: CoordinatorTab.map.systemImage)
            }
            .tag(CoordinatorTab.map)

            NavigationStack {
                VolunteerCoordinationView(sessionViewModel: sessionViewModel)
            }
            .tabItem {
                Label(CoordinatorTab.volunteers.title, systemImage: CoordinatorTab.volunteers.systemImage)
            }
            .tag(CoordinatorTab.volunteers)

            NavigationStack {
                CoordinatorOperationsView(sessionViewModel: sessionViewModel)
            }
            .tabItem {
                Label(CoordinatorTab.tools.title, systemImage: CoordinatorTab.tools.systemImage)
            }
            .tag(CoordinatorTab.tools)

            NavigationStack {
                ProfileView(sessionViewModel: sessionViewModel)
            }
            .tabItem {
                Label(CoordinatorTab.profile.title, systemImage: CoordinatorTab.profile.systemImage)
            }
            .tag(CoordinatorTab.profile)
        }
        .tint(.orange)
    }
}

private enum CoordinatorTab: Hashable {
    case requests
    case map
    case volunteers
    case tools
    case profile

    var title: String {
        switch self {
        case .requests: return "Requests"
        case .map: return "Map"
        case .volunteers: return "Volunteers"
        case .tools: return "Tools"
        case .profile: return "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .requests: return "rectangle.grid.2x2.fill"
        case .map: return "map.fill"
        case .volunteers: return "person.2.badge.gearshape.fill"
        case .tools: return "cross.case.circle.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }
}

//
//  AdminHomeView.swift
//  UrbanShield
//

import SwiftUI

struct AdminHomeView: View {
    let sessionViewModel: AuthSessionViewModel

    var body: some View {
        TabView {
            NavigationStack {
                AdminUserManagementView(sessionViewModel: sessionViewModel)
            }
            .tabItem {
                Label("Users", systemImage: "person.3.sequence.fill")
            }

            NavigationStack {
                CoordinatorDashboardView(sessionViewModel: sessionViewModel)
            }
            .tabItem {
                Label("Requests", systemImage: "rectangle.grid.2x2.fill")
            }

            NavigationStack {
                VolunteerCoordinationView(sessionViewModel: sessionViewModel)
            }
            .tabItem {
                Label("Volunteers", systemImage: "person.2.badge.gearshape.fill")
            }

            NavigationStack {
                AdminModerationView(sessionViewModel: sessionViewModel)
            }
            .tabItem {
                Label("Moderation", systemImage: "shield.lefthalf.filled.badge.checkmark")
            }

            NavigationStack {
                AdminActivityLogView(sessionViewModel: sessionViewModel)
            }
            .tabItem {
                Label("Activity", systemImage: "clock.arrow.2.circlepath")
            }

            NavigationStack {
                AdminSettingsView(sessionViewModel: sessionViewModel)
            }
            .tabItem {
                Label("Admin", systemImage: "crown.fill")
            }
        }
    }
}

private struct AdminSettingsView: View {
    let sessionViewModel: AuthSessionViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RequestCard {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "crown.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Admin Console")
                                .font(.title2.bold())

                            Text("Manage trusted coordinators and monitor request operations from the admin area.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button(role: .destructive) {
                    Task { await sessionViewModel.signOut() }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                }
                .buttonStyle(.bordered)

                NavigationLink {
                    NotificationsView(sessionViewModel: sessionViewModel)
                } label: {
                    Label("Open Notifications", systemImage: "bell.badge.fill")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
        }
        .background(RequestUI.background)
        .navigationTitle("Admin")
    }
}

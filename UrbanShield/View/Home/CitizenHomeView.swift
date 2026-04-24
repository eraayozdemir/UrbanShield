//
//  CitizenHomeView.swift
//  UrbanShield
//

import SwiftUI

struct CitizenHomeView: View {
    let sessionViewModel: AuthSessionViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        CreateRequestView(sessionViewModel: sessionViewModel)
                    } label: {
                        HomeActionRow(
                            icon: "plus.circle.fill",
                            title: "Create Help Request",
                            subtitle: "Report an emergency and share coordinates."
                        )
                    }

                    NavigationLink {
                        MyRequestsView(sessionViewModel: sessionViewModel)
                    } label: {
                        HomeActionRow(
                            icon: "list.bullet.rectangle.fill",
                            title: "My Requests",
                            subtitle: "View and manage your submitted requests."
                        )
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task { await sessionViewModel.signOut() }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("UrbanShield")
        }
    }
}

private struct HomeActionRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

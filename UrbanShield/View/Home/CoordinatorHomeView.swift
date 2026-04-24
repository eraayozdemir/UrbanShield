//
//  CoordinatorHomeView.swift
//  UrbanShield
//

import SwiftUI

struct CoordinatorHomeView: View {
    let sessionViewModel: AuthSessionViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    RequestCard {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "map.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 50, height: 50)
                                .background(Color.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Coordinator View")
                                    .font(.title2.bold())

                                Text("Coordinator routing is ready. Dispatch overview, regional monitoring, and assignment tools will be added after the citizen-volunteer flow.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    CoordinatorInfoRow(
                        icon: "point.3.connected.trianglepath.dotted",
                        title: "Request Flow",
                        subtitle: "Open requests can become confirmed, in progress, completed, or cancelled.",
                        tint: .orange
                    )

                    CoordinatorInfoRow(
                        icon: "person.crop.circle.badge.checkmark",
                        title: "Volunteer Assignment",
                        subtitle: "Volunteers are attached to requests after confirmation.",
                        tint: .green
                    )

                    Button(role: .destructive) {
                        Task { await sessionViewModel.signOut() }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)
            }
            .background(RequestUI.background)
            .navigationTitle("Coordinator")
        }
    }
}

private struct CoordinatorInfoRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RequestUI.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

//
//  AdminHomeView.swift
//  UrbanShield
//

import SwiftUI

struct AdminHomeView: View {
    let sessionViewModel: AuthSessionViewModel

    var body: some View {
        NavigationStack {
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

                                Text("App owner access for platform-level management. Moderation and system tools will be added in a later phase.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    AdminInfoRow(
                        icon: "person.3.sequence.fill",
                        title: "Role Routing Active",
                        subtitle: "Admin users land on this protected admin view.",
                        tint: .purple
                    )

                    AdminInfoRow(
                        icon: "lock.shield.fill",
                        title: "Owner Area",
                        subtitle: "Citizen and volunteer request actions are not mixed into admin mode.",
                        tint: .blue
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
            .navigationTitle("Admin")
        }
    }
}

private struct AdminInfoRow: View {
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

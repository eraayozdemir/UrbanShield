//
//  ProfileView.swift
//  UrbanShield
//

import SwiftUI

struct ProfileView: View {
    let sessionViewModel: AuthSessionViewModel

    private var currentUser: User? {
        if case .authenticated(let user) = sessionViewModel.session {
            return user
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let user = currentUser {
                    profileHeader(user)

                    RequestCard {
                        RequestSectionTitle(title: "Account", systemImage: "person.text.rectangle")

                        ProfileInfoRow(title: "Full Name", value: user.fullName, systemImage: "person.fill")
                        Divider()
                        ProfileInfoRow(title: "Email", value: user.email, systemImage: "envelope.fill")
                        Divider()
                        ProfileInfoRow(title: "Role", value: user.role.rawValue.capitalized, systemImage: "key.fill")
                    }

                    RequestCard {
                        RequestSectionTitle(title: "Security", systemImage: "lock.shield.fill")

                        ProfileInfoRow(
                            title: "Session",
                            value: "Authenticated",
                            systemImage: "checkmark.seal.fill",
                            tint: .green
                        )
                        Divider()
                        ProfileInfoRow(
                            title: "Member Since",
                            value: user.createdAt.formatted(date: .abbreviated, time: .omitted),
                            systemImage: "calendar"
                        )
                    }

                    Button(role: .destructive) {
                        Task { await sessionViewModel.signOut() }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 52)
                    }
                    .buttonStyle(.bordered)
                } else {
                    ContentUnavailableView(
                        "No Active Profile",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text("Sign in again to load your profile.")
                    )
                }
            }
            .padding(16)
        }
        .background(RequestUI.background)
        .navigationTitle("Profile")
    }

    private func profileHeader(_ user: User) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 86, height: 86)

                Text(initials(for: user.fullName))
                    .font(.title.bold())
                    .foregroundStyle(.white)
            }

            VStack(spacing: 4) {
                Text(user.fullName)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(user.email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text(user.role.rawValue.capitalized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.blue.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(RequestUI.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func initials(for name: String) -> String {
        let parts = name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)

        let initials = String(parts).uppercased()
        return initials.isEmpty ? "US" : initials
    }
}

private struct ProfileInfoRow: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .blue

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 0)
        }
    }
}

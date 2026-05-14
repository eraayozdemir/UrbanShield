//
//  AdminUserManagementView.swift
//  UrbanShield
//

import SwiftUI

struct AdminUserManagementView: View {
    let sessionViewModel: AuthSessionViewModel

    @State private var viewModel = AdminUserManagementViewModel()
    @State private var selectedRoleFilter: AdminRoleFilter = .all

    private var currentUser: User? {
        if case .authenticated(let user) = sessionViewModel.session {
            return user
        }
        return nil
    }

    private var filteredUsers: [ProfileUserRecord] {
        viewModel.users.filter { selectedRoleFilter.includes($0.roleValue) }
    }

    var body: some View {
        ZStack {
            RequestUI.background
                .ignoresSafeArea()

            if viewModel.isLoading && viewModel.users.isEmpty {
                AdminLoadingView(title: "Loading users...")
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        header
                            .padding(.top, 8)

                        roleFilter

                        if filteredUsers.isEmpty {
                            emptyState
                        } else {
                            ForEach(filteredUsers) { user in
                                AdminUserCard(
                                    user: user,
                                    isCurrentUser: user.id == currentUser?.id,
                                    isUpdating: viewModel.updatingUserId == user.id
                                ) { role in
                                    Task {
                                        await viewModel.updateRole(
                                            user: user,
                                            role: role,
                                            currentUser: currentUser
                                        )
                                        await sessionViewModel.refreshCurrentUser()
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 18)
                }
                .refreshable {
                    await reloadUsers()
                }
            }
        }
        .navigationTitle("Users")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await reloadUsers() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .overlay(alignment: .bottom) {
            if let error = viewModel.errorMessage {
                RequestErrorBanner(message: error)
            } else if let success = viewModel.successMessage {
                RequestInfoBanner(message: success, color: .green)
            }
        }
        .task {
            await reloadUsers()
        }
    }

    private func reloadUsers() async {
        await viewModel.loadUsers(currentUser: currentUser)
    }

    private var header: some View {
        RequestCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "person.3.sequence.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("User Roles")
                        .font(.title2.bold())

                    Text("Promote trusted users to coordinator, or manage admin access from inside UrbanShield.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var roleFilter: some View {
        Picker("Role Filter", selection: $selectedRoleFilter) {
            ForEach(AdminRoleFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Users",
            systemImage: "person.3",
            description: Text("No users match the selected role filter.")
        )
        .padding(.vertical, 40)
    }
}

private enum AdminRoleFilter: String, CaseIterable, Identifiable {
    case all
    case citizens
    case coordinators
    case admins

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .citizens: return "Citizen"
        case .coordinators: return "Coord"
        case .admins: return "Admin"
        }
    }

    func includes(_ role: UserRole) -> Bool {
        switch self {
        case .all: return true
        case .citizens: return role == .citizen || role == .volunteer
        case .coordinators: return role == .coordinator
        case .admins: return role == .admin
        }
    }
}

private struct AdminUserCard: View {
    let user: ProfileUserRecord
    let isCurrentUser: Bool
    let isUpdating: Bool
    let onRoleChange: (UserRole) -> Void

    var body: some View {
        RequestCard {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(roleColor.opacity(0.14))
                    Image(systemName: roleIcon)
                        .font(.headline)
                        .foregroundStyle(roleColor)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(user.fullName)
                            .font(.headline)
                            .lineLimit(1)
                        if isCurrentUser {
                            Text("You")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.purple.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    Text(user.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                AdminRoleChip(role: user.roleValue)
            }

            HStack(spacing: 8) {
                Label(user.availabilityValue.title, systemImage: "person.crop.circle.badge.checkmark")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Menu {
                    Button("Make Citizen") {
                        onRoleChange(.citizen)
                    }
                    Button("Make Coordinator") {
                        onRoleChange(.coordinator)
                    }
                    Button("Make Admin") {
                        onRoleChange(.admin)
                    }
                } label: {
                    if isUpdating {
                        ProgressView()
                    } else {
                        Label("Role", systemImage: "key.fill")
                            .font(.caption.weight(.semibold))
                    }
                }
                .disabled(isUpdating || isCurrentUser)
            }
        }
    }

    private var roleIcon: String {
        switch user.roleValue {
        case .citizen: return "person.fill"
        case .volunteer: return "checkmark.shield.fill"
        case .coordinator: return "rectangle.grid.2x2.fill"
        case .admin: return "crown.fill"
        }
    }

    private var roleColor: Color {
        switch user.roleValue {
        case .citizen: return .blue
        case .volunteer: return .green
        case .coordinator: return .orange
        case .admin: return .purple
        }
    }
}

private struct AdminRoleChip: View {
    let role: UserRole

    var body: some View {
        Text(role.rawValue.capitalized)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var color: Color {
        switch role {
        case .citizen: return .blue
        case .volunteer: return .green
        case .coordinator: return .orange
        case .admin: return .purple
        }
    }
}

private struct AdminLoadingView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

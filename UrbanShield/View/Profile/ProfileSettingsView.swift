//
//  ProfileSettingsView.swift
//  UrbanShield
//

import Observation
import SwiftUI

struct ProfileSettingsView: View {
    let sessionViewModel: AuthSessionViewModel

    @State private var viewModel: ProfileSettingsViewModel

    init(sessionViewModel: AuthSessionViewModel, user: User) {
        self.sessionViewModel = sessionViewModel
        _viewModel = State(initialValue: ProfileSettingsViewModel(user: user))
    }

    var body: some View {
        Form {
            Section {
                SettingsProfileHeader(
                    fullName: viewModel.fullName,
                    email: viewModel.email
                )
            }

            Section {
                NavigationLink {
                    EditProfileSettingsView(
                        sessionViewModel: sessionViewModel,
                        viewModel: viewModel
                    )
                } label: {
                    SettingsValueRow(
                        title: "Profile",
                        value: viewModel.fullName,
                        systemImage: "person.fill",
                        iconColor: .blue
                    )
                }

                SettingsValueRow(
                    title: "Email",
                    value: viewModel.email,
                    systemImage: "envelope.fill",
                    iconColor: .gray
                )
            } header: {
                Text("Apple ID")
            }

            Section {
                NavigationLink {
                    ChangePasswordSettingsView(viewModel: viewModel)
                } label: {
                    SettingsNavigationRow(
                        title: "Change Password",
                        systemImage: "key.fill",
                        iconColor: .orange
                    )
                }
            } header: {
                Text("Security")
            }

            Section {
                NavigationLink {
                    VolunteerProfileSettingsView(
                        sessionViewModel: sessionViewModel,
                        viewModel: viewModel
                    )
                } label: {
                    SettingsValueRow(
                        title: "Availability",
                        value: viewModel.availabilityStatus.title,
                        systemImage: "hands.sparkles.fill",
                        iconColor: viewModel.availabilityColor
                    )
                }

                SettingsValueRow(
                    title: "Skills",
                    value: viewModel.volunteerSkillSummary,
                    systemImage: "star.fill",
                    iconColor: .green
                )
            } header: {
                Text("Volunteer")
            } footer: {
                Text("Set your readiness before accepting nearby requests. Accepted requests automatically mark you as busy.")
            }

            if let message = viewModel.statusMessage {
                Section {
                    SettingsStatusRow(
                        message: message,
                        isError: viewModel.statusIsError
                    )
                }
            }

            Section {
                NavigationLink {
                    SignOutSettingsView(sessionViewModel: sessionViewModel)
                } label: {
                    SettingsNavigationRow(
                        title: "Sign Out",
                        systemImage: "rectangle.portrait.and.arrow.right",
                        iconColor: .red,
                        textColor: .red
                    )
                }
            } header: {
                Text("Session")
            }

            Section {
                NavigationLink {
                    DeleteAccountSettingsView(
                        sessionViewModel: sessionViewModel,
                        viewModel: viewModel
                    )
                } label: {
                    SettingsNavigationRow(
                        title: "Delete Account",
                        systemImage: "trash.fill",
                        iconColor: .red,
                        textColor: .red
                    )
                }
            } footer: {
                Text("Deleting your account is permanent and cannot be undone.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EditProfileSettingsView: View {
    let sessionViewModel: AuthSessionViewModel
    @Bindable var viewModel: ProfileSettingsViewModel

    var body: some View {
        Form {
            Section {
                SettingsFieldRow(
                    title: "Name",
                    systemImage: "person.fill",
                    iconColor: .blue
                ) {
                    TextField("Full Name", text: $viewModel.fullName)
                        .textContentType(.name)
                        .multilineTextAlignment(.trailing)
                        .submitLabel(.done)
                }

                SettingsValueRow(
                    title: "Email",
                    value: viewModel.email,
                    systemImage: "envelope.fill",
                    iconColor: .gray
                )
            } footer: {
                Text("Your profile name is visible on your account inside UrbanShield.")
            }

            if let message = viewModel.statusMessage {
                Section {
                    SettingsStatusRow(
                        message: message,
                        isError: viewModel.statusIsError
                    )
                }
            }

            Section {
                Button {
                    Task {
                        if let user = await viewModel.updateProfile() {
                            sessionViewModel.setAuthenticated(user)
                        }
                    }
                } label: {
                    SettingsActionRow(
                        title: "Save Profile",
                        systemImage: "checkmark.circle.fill",
                        iconColor: .green,
                        isLoading: viewModel.isUpdatingProfile
                    )
                }
                .disabled(!viewModel.canUpdateProfile)
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ChangePasswordSettingsView: View {
    @Bindable var viewModel: ProfileSettingsViewModel

    var body: some View {
        Form {
            Section {
                SettingsFieldRow(
                    title: "New Password",
                    systemImage: "lock.fill",
                    iconColor: .orange
                ) {
                    SecureField("Required", text: $viewModel.newPassword)
                        .textContentType(.newPassword)
                        .multilineTextAlignment(.trailing)
                }

                SettingsFieldRow(
                    title: "Confirm",
                    systemImage: "lock.rotation",
                    iconColor: .orange
                ) {
                    SecureField("Required", text: $viewModel.confirmPassword)
                        .textContentType(.newPassword)
                        .multilineTextAlignment(.trailing)
                }

                if !viewModel.newPassword.isEmpty {
                    Text(viewModel.passwordHint)
                        .font(.caption)
                        .foregroundStyle(viewModel.isPasswordValid ? .green : .secondary)
                }

            } footer: {
                Text("Use at least 8 characters with uppercase, lowercase, number, and special character.")
            }

            if let message = viewModel.statusMessage {
                Section {
                    SettingsStatusRow(
                        message: message,
                        isError: viewModel.statusIsError
                    )
                }
            }

            Section {
                Button {
                    Task { await viewModel.updatePassword() }
                } label: {
                    SettingsActionRow(
                        title: "Change Password",
                        systemImage: "key.fill",
                        iconColor: .blue,
                        isLoading: viewModel.isUpdatingPassword
                    )
                }
                .disabled(!viewModel.canUpdatePassword)
            }
        }
        .navigationTitle("Password")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct VolunteerProfileSettingsView: View {
    let sessionViewModel: AuthSessionViewModel
    @Bindable var viewModel: ProfileSettingsViewModel

    private let availabilityOptions: [VolunteerAvailability] = [.available, .offline]

    var body: some View {
        Form {
            Section {
                if viewModel.availabilityStatus == .busy {
                    SettingsValueRow(
                        title: "Availability",
                        value: VolunteerAvailability.busy.title,
                        systemImage: "clock.fill",
                        iconColor: .orange
                    )
                } else {
                    Picker("Availability", selection: $viewModel.availabilityStatus) {
                        ForEach(availabilityOptions) { status in
                            Text(status.title).tag(status)
                        }
                    }
                }
            } footer: {
                Text(viewModel.availabilityStatus == .busy ? "You are busy because you have an accepted request. Complete your active task to become available again." : "Available volunteers can accept nearby requests. Offline volunteers cannot accept new tasks.")
            }

            Section {
                ForEach(Array(VolunteerSkill.allCases)) { skill in
                    Button {
                        viewModel.toggleSkill(skill)
                    } label: {
                        HStack(spacing: 12) {
                            SettingsIcon(systemImage: viewModel.hasSkill(skill) ? "checkmark.circle.fill" : "circle", color: viewModel.hasSkill(skill) ? .green : .gray)

                            Text(skill.title)
                                .foregroundStyle(.primary)

                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Skills")
            } footer: {
                Text("Skills are used to match volunteers with request types such as medical, flood, fire, accident, and earthquake.")
            }

            if let message = viewModel.statusMessage {
                Section {
                    SettingsStatusRow(
                        message: message,
                        isError: viewModel.statusIsError
                    )
                }
            }

            Section {
                Button {
                    Task {
                        if let user = await viewModel.updateVolunteerProfile() {
                            sessionViewModel.setAuthenticated(user)
                        }
                    }
                } label: {
                    SettingsActionRow(
                        title: "Save Volunteer Profile",
                        systemImage: "checkmark.circle.fill",
                        iconColor: .green,
                        isLoading: viewModel.isUpdatingVolunteerProfile
                    )
                }
                .disabled(!viewModel.canUpdateVolunteerProfile)
            }
        }
        .navigationTitle("Volunteer Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SignOutSettingsView: View {
    let sessionViewModel: AuthSessionViewModel

    var body: some View {
        Form {
            Section {
                SettingsActionRow(
                    title: "Signed In",
                    systemImage: "checkmark.seal.fill",
                    iconColor: .green
                )
            } footer: {
                Text("Signing out removes this session from the device. You can sign in again with your email and password.")
            }

            Section {
                Button(role: .destructive) {
                    Task { await sessionViewModel.signOut() }
                } label: {
                    SettingsActionRow(
                        title: "Sign Out",
                        systemImage: "rectangle.portrait.and.arrow.right",
                        iconColor: .red,
                        textColor: .red
                    )
                }
            }
        }
        .navigationTitle("Sign Out")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DeleteAccountSettingsView: View {
    let sessionViewModel: AuthSessionViewModel
    @Bindable var viewModel: ProfileSettingsViewModel

    @State private var showDeleteConfirmation = false

    var body: some View {
        Form {
            Section {
                SettingsValueRow(
                    title: "Account",
                    value: viewModel.email,
                    systemImage: "person.crop.circle.badge.xmark.fill",
                    iconColor: .red
                )
            } footer: {
                Text("This action permanently deletes your account. It cannot be undone.")
            }

            if let message = viewModel.statusMessage {
                Section {
                    SettingsStatusRow(
                        message: message,
                        isError: viewModel.statusIsError
                    )
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    SettingsActionRow(
                        title: "Delete Account",
                        systemImage: "trash.fill",
                        iconColor: .red,
                        textColor: .red,
                        isLoading: viewModel.isDeletingAccount
                    )
                }
                .disabled(viewModel.isDeletingAccount)
            }
        }
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Account?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await viewModel.deleteAccount(using: sessionViewModel)
                    } catch {
                        viewModel.setError(error.localizedDescription)
                    }
                }
            }
        } message: {
            Text("This will permanently delete your account and sign you out.")
        }
    }
}

private struct SettingsProfileHeader: View {
    let fullName: String
    let email: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text(initials)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 3) {
                Text(fullName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.vertical, 6)
    }

    private var initials: String {
        let parts = fullName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)

        let initials = String(parts).uppercased()
        return initials.isEmpty ? "US" : initials
    }
}

private struct SettingsIcon: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct SettingsFieldRow<Content: View>: View {
    let title: String
    let systemImage: String
    let iconColor: Color
    let content: Content

    init(
        title: String,
        systemImage: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.iconColor = iconColor
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemImage: systemImage, color: iconColor)

            Text(title)

            Spacer(minLength: 12)

            content
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String
    let systemImage: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemImage: systemImage, color: iconColor)

            Text(title)

            Spacer(minLength: 12)

            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(minHeight: 44)
    }
}

private struct SettingsNavigationRow: View {
    let title: String
    let systemImage: String
    let iconColor: Color
    var textColor: Color = .primary

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemImage: systemImage, color: iconColor)

            Text(title)
                .foregroundStyle(textColor)
        }
        .frame(minHeight: 44)
    }
}

private struct SettingsActionRow: View {
    let title: String
    let systemImage: String
    let iconColor: Color
    var textColor: Color = .primary
    var isLoading = false

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemImage: systemImage, color: iconColor)

            Text(title)
                .foregroundStyle(textColor)

            Spacer()

            if isLoading {
                ProgressView()
            }
        }
        .frame(minHeight: 44)
    }
}

private struct SettingsStatusRow: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(
                systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                color: isError ? .red : .green
            )

            Text(message)
                .font(.subheadline)
                .foregroundStyle(isError ? .red : .green)
        }
        .frame(minHeight: 44)
    }
}

@MainActor
@Observable
private final class ProfileSettingsViewModel {
    var fullName: String
    let email: String
    var availabilityStatus: VolunteerAvailability
    var volunteerSkills: [VolunteerSkill]
    var newPassword = ""
    var confirmPassword = ""
    var isUpdatingProfile = false
    var isUpdatingVolunteerProfile = false
    var isUpdatingPassword = false
    var isDeletingAccount = false
    var statusMessage: String?
    var statusIsError = false

    private var originalFullName: String
    private var originalAvailabilityStatus: VolunteerAvailability
    private var originalVolunteerSkills: [VolunteerSkill]

    init(user: User) {
        fullName = user.fullName
        originalFullName = user.fullName
        email = user.email
        availabilityStatus = user.availabilityStatus
        originalAvailabilityStatus = user.availabilityStatus
        volunteerSkills = user.volunteerSkills
        originalVolunteerSkills = user.volunteerSkills
    }

    var canUpdateProfile: Bool {
        !isUpdatingProfile
            && !trimmedFullName.isEmpty
            && trimmedFullName != originalFullName
    }

    var canUpdatePassword: Bool {
        !isUpdatingPassword && isPasswordValid && newPassword == confirmPassword
    }

    var canUpdateVolunteerProfile: Bool {
        !isUpdatingVolunteerProfile
            && !volunteerSkills.isEmpty
            && (availabilityStatus != originalAvailabilityStatus || normalizedVolunteerSkills != normalizedOriginalVolunteerSkills)
    }

    var volunteerSkillSummary: String {
        volunteerSkills.isEmpty ? "Not set" : "\(volunteerSkills.count) selected"
    }

    var availabilityColor: Color {
        switch availabilityStatus {
        case .available: return .green
        case .busy: return .orange
        case .offline: return .gray
        }
    }

    var isPasswordValid: Bool {
        newPassword.count >= 8
            && newPassword.range(of: #"[A-Z]"#, options: .regularExpression) != nil
            && newPassword.range(of: #"[a-z]"#, options: .regularExpression) != nil
            && newPassword.range(of: #"[0-9]"#, options: .regularExpression) != nil
            && newPassword.range(of: #"[!@#$%^&*()_+\-=\[\]{};'\\:\"|<>?,./`~]"#, options: .regularExpression) != nil
    }

    var passwordHint: String {
        if !isPasswordValid {
            return "Use at least 8 characters with uppercase, lowercase, number, and special character."
        }

        if newPassword != confirmPassword {
            return "Passwords must match."
        }

        return "Password requirements met."
    }

    func updateProfile() async -> User? {
        isUpdatingProfile = true
        clearStatus()
        defer { isUpdatingProfile = false }

        do {
            let user = try await AuthService.shared.updateProfile(fullName: trimmedFullName)
            originalFullName = user.fullName
            fullName = user.fullName
            setSuccess("Profile updated.")
            return user
        } catch {
            setError(error.localizedDescription)
            return nil
        }
    }

    func updateVolunteerProfile() async -> User? {
        isUpdatingVolunteerProfile = true
        clearStatus()
        defer { isUpdatingVolunteerProfile = false }

        guard !volunteerSkills.isEmpty else {
            setError("Select at least one volunteer skill.")
            return nil
        }

        do {
            let user = try await AuthService.shared.updateVolunteerProfile(
                availabilityStatus: availabilityStatus,
                skills: volunteerSkills
            )
            availabilityStatus = user.availabilityStatus
            originalAvailabilityStatus = user.availabilityStatus
            volunteerSkills = user.volunteerSkills
            originalVolunteerSkills = user.volunteerSkills
            setSuccess("Volunteer profile updated.")
            return user
        } catch {
            setError(error.localizedDescription)
            return nil
        }
    }

    func hasSkill(_ skill: VolunteerSkill) -> Bool {
        volunteerSkills.contains(skill)
    }

    func toggleSkill(_ skill: VolunteerSkill) {
        if volunteerSkills.contains(skill) {
            volunteerSkills.removeAll { $0 == skill }
        } else {
            volunteerSkills.append(skill)
            volunteerSkills.sort { $0.title < $1.title }
        }
    }

    func updatePassword() async {
        isUpdatingPassword = true
        clearStatus()
        defer { isUpdatingPassword = false }

        do {
            try await AuthService.shared.updatePassword(newPassword)
            newPassword = ""
            confirmPassword = ""
            setSuccess("Password updated.")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func deleteAccount(using sessionViewModel: AuthSessionViewModel) async throws {
        isDeletingAccount = true
        clearStatus()
        defer { isDeletingAccount = false }

        do {
            try await sessionViewModel.deleteAccount()
        } catch {
            setError(error.localizedDescription)
            throw error
        }
    }

    func setError(_ message: String) {
        statusMessage = message
        statusIsError = true
    }

    private var trimmedFullName: String {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedVolunteerSkills: [String] {
        volunteerSkills.map(\.rawValue).sorted()
    }

    private var normalizedOriginalVolunteerSkills: [String] {
        originalVolunteerSkills.map(\.rawValue).sorted()
    }

    private func clearStatus() {
        statusMessage = nil
        statusIsError = false
    }

    private func setSuccess(_ message: String) {
        statusMessage = message
        statusIsError = false
    }
}

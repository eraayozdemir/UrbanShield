//
//  ProfileSettingsView.swift
//  UrbanShield
//

import Observation
import SwiftUI

struct ProfileSettingsView: View {
    let sessionViewModel: AuthSessionViewModel

    @State private var viewModel: ProfileSettingsViewModel
    @State private var showDeleteConfirmation = false

    init(sessionViewModel: AuthSessionViewModel, user: User) {
        self.sessionViewModel = sessionViewModel
        _viewModel = State(initialValue: ProfileSettingsViewModel(user: user))
    }

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Full Name", text: $viewModel.fullName)
                    .textContentType(.name)

                Text(viewModel.email)
                    .foregroundStyle(.secondary)

                Button {
                    Task {
                        if let user = await viewModel.updateProfile() {
                            sessionViewModel.setAuthenticated(user)
                        }
                    }
                } label: {
                    settingsButtonLabel("Save Profile", isLoading: viewModel.isUpdatingProfile)
                }
                .disabled(!viewModel.canUpdateProfile)
            }

            Section("Password") {
                SecureField("New Password", text: $viewModel.newPassword)
                    .textContentType(.newPassword)

                SecureField("Confirm New Password", text: $viewModel.confirmPassword)
                    .textContentType(.newPassword)

                if !viewModel.newPassword.isEmpty {
                    Text(viewModel.passwordHint)
                        .font(.caption)
                        .foregroundStyle(viewModel.isPasswordValid ? .green : .secondary)
                }

                Button {
                    Task { await viewModel.updatePassword() }
                } label: {
                    settingsButtonLabel("Change Password", isLoading: viewModel.isUpdatingPassword)
                }
                .disabled(!viewModel.canUpdatePassword)
            }

            if let message = viewModel.statusMessage {
                Section {
                    Text(message)
                        .foregroundStyle(viewModel.statusIsError ? .red : .green)
                }
            }

            Section {
                Button(role: .destructive) {
                    Task { await sessionViewModel.signOut() }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Account", systemImage: "trash.fill")
                }
                .disabled(viewModel.isDeletingAccount)
            } footer: {
                Text("Deleting your account is permanent and cannot be undone.")
            }
        }
        .navigationTitle("Settings")
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

    private func settingsButtonLabel(_ title: String, isLoading: Bool) -> some View {
        HStack {
            if isLoading {
                ProgressView()
            }

            Text(title)
        }
    }
}

@MainActor
@Observable
private final class ProfileSettingsViewModel {
    var fullName: String
    let email: String
    var newPassword = ""
    var confirmPassword = ""
    var isUpdatingProfile = false
    var isUpdatingPassword = false
    var isDeletingAccount = false
    var statusMessage: String?
    var statusIsError = false

    private var originalFullName: String

    init(user: User) {
        fullName = user.fullName
        originalFullName = user.fullName
        email = user.email
    }

    var canUpdateProfile: Bool {
        !isUpdatingProfile
            && !trimmedFullName.isEmpty
            && trimmedFullName != originalFullName
    }

    var canUpdatePassword: Bool {
        !isUpdatingPassword && isPasswordValid && newPassword == confirmPassword
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

    private func clearStatus() {
        statusMessage = nil
        statusIsError = false
    }

    private func setSuccess(_ message: String) {
        statusMessage = message
        statusIsError = false
    }
}

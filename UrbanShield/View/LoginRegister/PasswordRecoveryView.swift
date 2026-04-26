//
//  PasswordRecoveryView.swift
//  UrbanShield
//

import Observation
import SwiftUI

struct PasswordRecoveryView: View {
    let sessionViewModel: AuthSessionViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = PasswordRecoveryViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New Password", text: $viewModel.password)
                        .textContentType(.newPassword)

                    SecureField("Confirm New Password", text: $viewModel.confirmPassword)
                        .textContentType(.newPassword)
                } footer: {
                    Text("Use at least 8 characters with uppercase, lowercase, number, and special character.")
                }

                if let message = viewModel.statusMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(viewModel.statusIsError ? .red : .green)
                    }
                }

                Section {
                    Button {
                        Task {
                            if await viewModel.updatePassword() {
                                await sessionViewModel.signOut()
                                sessionViewModel.isPasswordRecoveryFlow = false
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView()
                            }

                            Text("Update Password")
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                }
            }
            .navigationTitle("New Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        sessionViewModel.isPasswordRecoveryFlow = false
                        dismiss()
                    }
                }
            }
        }
    }
}

@MainActor
@Observable
private final class PasswordRecoveryViewModel {
    var password = ""
    var confirmPassword = ""
    var isLoading = false
    var statusMessage: String?
    var statusIsError = false

    var canSubmit: Bool {
        !isLoading && isPasswordValid && password == confirmPassword
    }

    private var isPasswordValid: Bool {
        password.count >= 8
            && password.range(of: #"[A-Z]"#, options: .regularExpression) != nil
            && password.range(of: #"[a-z]"#, options: .regularExpression) != nil
            && password.range(of: #"[0-9]"#, options: .regularExpression) != nil
            && password.range(of: #"[!@#$%^&*()_+\-=\[\]{};'\\:\"|<>?,./`~]"#, options: .regularExpression) != nil
    }

    func updatePassword() async -> Bool {
        isLoading = true
        statusMessage = nil
        statusIsError = false
        defer { isLoading = false }

        do {
            try await AuthService.shared.updatePassword(password)
            statusMessage = "Password updated. Please sign in with your new password."
            return true
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
            return false
        }
    }
}

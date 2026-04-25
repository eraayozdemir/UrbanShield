//
//  ForgotPasswordView.swift
//  UrbanShield
//

import Observation
import SwiftUI

struct ForgotPasswordView: View {
    @State private var viewModel: ForgotPasswordViewModel

    init(email: String) {
        _viewModel = State(initialValue: ForgotPasswordViewModel(email: email))
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "lock.rotation")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue)

                Text("Forgot Password")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text("Enter your email and we will send password reset instructions.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                TextField("Email", text: $viewModel.email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textContentType(.emailAddress)
                    .textFieldStyle(.roundedBorder)

                if let statusMessage = viewModel.statusMessage {
                    Text(statusMessage)
                        .foregroundStyle(viewModel.statusIsError ? .red : .green)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await viewModel.sendResetEmail() }
                } label: {
                    Group {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Send Reset Email")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSubmit)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .navigationTitle("Reset Password")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
@Observable
private final class ForgotPasswordViewModel {
    var email: String
    var isLoading = false
    var statusMessage: String?
    var statusIsError = false

    init(email: String) {
        self.email = email
    }

    var canSubmit: Bool {
        !isLoading && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func sendResetEmail() async {
        isLoading = true
        statusMessage = nil
        statusIsError = false
        defer { isLoading = false }

        do {
            try await AuthService.shared.sendPasswordReset(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            statusMessage = "Password reset email sent. Please check your inbox."
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }
}

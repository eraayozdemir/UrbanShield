//
//  RegisterView.swift
//  UrbanShield
//

import SwiftUI

struct RegisterView: View {
    let sessionViewModel: AuthSessionViewModel

    @State private var viewModel = RegisterViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Header
            VStack(spacing: 8) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue)

                Text("Create Account")
                    .font(.largeTitle.bold())

                Text("Join UrbanShield as a citizen")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Form
            VStack(spacing: 12) {
                TextField("Full Name", text: $viewModel.fullName)
                    .textFieldStyle(.roundedBorder)

                TextField("Email", text: $viewModel.email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $viewModel.password)
                    .textFieldStyle(.roundedBorder)

                SecureField("Confirm Password", text: $viewModel.confirmPassword)
                    .textFieldStyle(.roundedBorder)

                PasswordRequirementsView(
                    requirements: viewModel.passwordRequirements,
                    passwordsMatch: viewModel.doPasswordsMatch,
                    confirmPasswordIsEmpty: viewModel.confirmPassword.isEmpty
                )

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task {
                        _ = await viewModel.signUp()
                    }
                } label: {
                    Group {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Create Account")
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

            Button("Already have an account? Sign In") {
                dismiss()
            }
            .font(.footnote)
            .padding(.bottom)
        }
        .padding(.horizontal, 24)
        .navigationTitle("Register")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Account Created", isPresented: $viewModel.didSignUp) {
            Button("Go to Login") {
                dismiss()
            }
        } message: {
            Text("Your account was created successfully. Please sign in with your email and password.")
        }
    }
}

private struct PasswordRequirementsView: View {
    let requirements: [PasswordRequirement]
    let passwordsMatch: Bool
    let confirmPasswordIsEmpty: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(requirements) { requirement in
                RequirementRow(title: requirement.title, isMet: requirement.isMet)
            }

            RequirementRow(
                title: "Passwords match",
                isMet: passwordsMatch,
                isNeutral: confirmPasswordIsEmpty
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct RequirementRow: View {
    let title: String
    let isMet: Bool
    var isNeutral: Bool = false

    var body: some View {
        Label {
            Text(title)
                .font(.caption)
        } icon: {
            Image(systemName: iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(iconColor)
        }
        .foregroundStyle(isNeutral ? Color.secondary : (isMet ? Color.green : Color.secondary))
    }

    private var iconName: String {
        if isNeutral { return "circle" }
        return isMet ? "checkmark.circle.fill" : "circle"
    }

    private var iconColor: Color {
        if isNeutral { return .secondary }
        return isMet ? .green : .secondary
    }
}

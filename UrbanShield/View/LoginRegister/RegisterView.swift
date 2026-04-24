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

                SecureField("Password (min. 6 characters)", text: $viewModel.password)
                    .textFieldStyle(.roundedBorder)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task {
                        if let user = await viewModel.signUp() {
                            sessionViewModel.setAuthenticated(user)
                        }
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
                .disabled(viewModel.isLoading || viewModel.fullName.isEmpty || viewModel.email.isEmpty || viewModel.password.count < 6)
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
    }
}

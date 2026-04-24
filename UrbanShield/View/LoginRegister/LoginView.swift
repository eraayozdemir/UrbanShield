//
//  LoginView.swift
//  UrbanShield
//

import SwiftUI

struct LoginView: View {
    let sessionViewModel: AuthSessionViewModel

    @State private var viewModel = LoginViewModel()
    @State private var showRegister = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                // Header
                VStack(spacing: 8) {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.blue)

                    Text("UrbanShield")
                        .font(.largeTitle.bold())

                    Text("Sign in to continue")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Form
                VStack(spacing: 12) {
                    TextField("Email", text: $viewModel.email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .textFieldStyle(.roundedBorder)

                    SecureField("Password", text: $viewModel.password)
                        .textFieldStyle(.roundedBorder)

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task {
                            if let user = await viewModel.signIn() {
                                sessionViewModel.setAuthenticated(user)
                            }
                        }
                    } label: {
                        Group {
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Sign In")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isLoading || viewModel.email.isEmpty || viewModel.password.isEmpty)
                }

                Spacer()

                // Navigate to Register
                Button("Don't have an account? Sign Up") {
                    showRegister = true
                }
                .font(.footnote)
                .padding(.bottom)
            }
            .padding(.horizontal, 24)
            .navigationDestination(isPresented: $showRegister) {
                RegisterView(sessionViewModel: sessionViewModel)
            }
        }
    }
}

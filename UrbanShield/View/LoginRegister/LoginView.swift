//
//  LoginView.swift
//  UrbanShield
//

import SwiftUI

struct LoginView: View {
    let sessionViewModel: AuthSessionViewModel

    @State private var viewModel = LoginViewModel()
    @State private var showRegister = false
    @State private var showForgotPassword = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                // Başlık
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

                    Button("Forgot Password?") {
                        showForgotPassword = true
                    }
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    if let error = viewModel.errorMessage {
                        Label {
                            Text(error)
                                .font(.caption.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

                // Register ekranına geçiş
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
            .navigationDestination(isPresented: $showForgotPassword) {
                ForgotPasswordView(email: viewModel.email)
            }
            .task(id: viewModel.errorMessage) {
                guard let error = viewModel.errorMessage else { return }
                try? await Task.sleep(for: .seconds(4))
                if viewModel.errorMessage == error {
                    viewModel.errorMessage = nil
                }
            }
        }
    }
}

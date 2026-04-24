//
//  CreateRequestView.swift
//  UrbanShield
//

import SwiftUI

struct CreateRequestView: View {
    let sessionViewModel: AuthSessionViewModel

    @State private var viewModel = CreateRequestViewModel()
    @Environment(\.dismiss) private var dismiss

    private var currentUser: User? {
        if case .authenticated(let user) = sessionViewModel.session {
            return user
        }
        return nil
    }

    var body: some View {
        Form {
            Section("Request Details") {
                Picker("Request Type", selection: $viewModel.requestType) {
                    ForEach(HelpRequestType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }

                Picker("Urgency", selection: $viewModel.urgencyLevel) {
                    ForEach(HelpRequestUrgency.allCases) { urgency in
                        Text(urgency.title).tag(urgency)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $viewModel.description)
                        .frame(minHeight: 120)
                }
            }

            Section("Location Coordinates") {
                TextField("Latitude", text: $viewModel.latitude)
                    .keyboardType(.decimalPad)

                TextField("Longitude", text: $viewModel.longitude)
                    .keyboardType(.decimalPad)
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task {
                        _ = await viewModel.submit(citizenId: currentUser?.id)
                    }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Text("Submit Request")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.isLoading)
            }
        }
        .navigationTitle("Create Request")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Request Submitted", isPresented: $viewModel.didSubmit) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your help request has been created.")
        }
    }
}

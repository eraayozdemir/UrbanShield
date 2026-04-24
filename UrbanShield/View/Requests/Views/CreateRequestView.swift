//
//  CreateRequestView.swift
//  UrbanShield
//

import SwiftUI

struct CreateRequestView: View {
    let sessionViewModel: AuthSessionViewModel

    @State private var viewModel = CreateRequestViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    enum Field {
        case description
        case latitude
        case longitude
    }

    private var currentUser: User? {
        if case .authenticated(let user) = sessionViewModel.session {
            return user
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                DraftSummaryCard(
                    requestType: viewModel.requestType,
                    urgency: viewModel.urgencyLevel
                )

                RequestCard {
                    RequestSectionTitle(title: "Emergency Type", systemImage: "square.grid.2x2")
                    RequestTypeGrid(selection: $viewModel.requestType)
                }

                RequestCard {
                    RequestSectionTitle(title: "Urgency Level", systemImage: "gauge.with.needle")
                    UrgencyGrid(selection: $viewModel.urgencyLevel)
                }

                RequestCard {
                    RequestSectionTitle(title: "Situation Details", systemImage: "text.alignleft")

                    TextEditor(text: $viewModel.description)
                        .focused($focusedField, equals: .description)
                        .frame(minHeight: 132)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if viewModel.description.isEmpty {
                                Text("Describe the emergency, injuries, visible risks, and access details.")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 18)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                RequestCard {
                    RequestSectionTitle(title: "Manual Location", systemImage: "location.fill")

                    VStack(spacing: 12) {
                        CoordinateField(
                            title: "Latitude",
                            text: $viewModel.latitude,
                            focusedField: $focusedField,
                            field: .latitude,
                            example: "41.0082"
                        )

                        CoordinateField(
                            title: "Longitude",
                            text: $viewModel.longitude,
                            focusedField: $focusedField,
                            field: .longitude,
                            example: "28.9784"
                        )
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 84)
        }
        .background(RequestUI.background)
        .navigationTitle("Create Request")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if let error = viewModel.errorMessage {
                    RequestErrorBanner(message: error)
                        .padding(.bottom, -4)
                }

                RequestPrimaryButton(
                    title: "Submit Request",
                    systemImage: "paperplane.fill",
                    isLoading: viewModel.isLoading
                ) {
                    focusedField = nil
                    Task {
                        _ = await viewModel.submit(citizenId: currentUser?.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .background(.regularMaterial)
        }
        .scrollDismissesKeyboard(.interactively)
        .alert("Request Submitted", isPresented: $viewModel.didSubmit) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your help request has been created.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Emergency Report")
                        .font(.title.bold())
                        .foregroundStyle(.white)

                    Text("Share the essential details responders need first.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "cross.case.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                    .frame(width: 48, height: 48)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.red, .orange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct DraftSummaryCard: View {
    let requestType: HelpRequestType
    let urgency: HelpRequestUrgency

    var body: some View {
        HStack(spacing: 12) {
            SummaryIcon(
                systemImage: RequestUI.requestIcon(requestType),
                color: RequestUI.urgencyColor(urgency)
            )

            VStack(alignment: .leading, spacing: 5) {
                Text("Draft Summary")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(requestType.title) • \(urgency.title) urgency")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer()

            RequestUrgencyChip(urgency: urgency)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RequestUI.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SummaryIcon: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.headline)
            .foregroundStyle(color)
            .frame(width: 42, height: 42)
            .background(color.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct RequestTypeGrid: View {
    @Binding var selection: HelpRequestType

    private let columns = [
        GridItem(.adaptive(minimum: 104), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(HelpRequestType.allCases) { type in
                SelectableTile(
                    title: type.title,
                    systemImage: RequestUI.requestIcon(type),
                    isSelected: selection == type,
                    color: .blue
                ) {
                    selection = type
                }
            }
        }
    }
}

private struct UrgencyGrid: View {
    @Binding var selection: HelpRequestUrgency

    private let columns = [
        GridItem(.adaptive(minimum: 104), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(HelpRequestUrgency.allCases) { urgency in
                SelectableTile(
                    title: urgency.title,
                    systemImage: "exclamationmark.triangle.fill",
                    isSelected: selection == urgency,
                    color: RequestUI.urgencyColor(urgency)
                ) {
                    selection = urgency
                }
            }
        }
    }
}

private struct SelectableTile: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .white : color)
                    .frame(width: 34, height: 34)
                    .background(isSelected ? color : color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(color)
                    }
                }
            }
            .foregroundStyle(.primary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 92)
            .background(isSelected ? color.opacity(0.12) : Color(.tertiarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? color : Color(.separator), lineWidth: isSelected ? 1.5 : 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct CoordinateField: View {
    let title: String
    @Binding var text: String
    var focusedField: FocusState<CreateRequestView.Field?>.Binding
    let field: CreateRequestView.Field
    let example: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            TextField(example, text: $text)
                .focused(focusedField, equals: field)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

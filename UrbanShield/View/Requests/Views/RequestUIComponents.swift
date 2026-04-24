//
//  RequestUIComponents.swift
//  UrbanShield
//

import SwiftUI

enum RequestUI {
    static let background = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)

    static func statusColor(_ status: HelpRequestStatus) -> Color {
        switch status {
        case .open: return .blue
        case .confirmed: return .purple
        case .inProgress: return .orange
        case .completed: return .green
        case .cancelled: return .red
        }
    }

    static func urgencyColor(_ urgency: HelpRequestUrgency) -> Color {
        switch urgency {
        case .low: return .green
        case .medium: return .blue
        case .high: return .orange
        case .critical: return .red
        }
    }

    static func requestIcon(_ type: HelpRequestType) -> String {
        switch type {
        case .earthquake: return "waveform.path.ecg.rectangle"
        case .fire: return "flame.fill"
        case .flood: return "drop.fill"
        case .accident: return "car.side.fill"
        case .medical: return "cross.case.fill"
        case .other: return "exclamationmark.bubble.fill"
        }
    }
}

struct RequestCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RequestUI.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct RequestSectionTitle: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

struct RequestStatusChip: View {
    let status: HelpRequestStatus

    var body: some View {
        Text(status.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(RequestUI.statusColor(status))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RequestUI.statusColor(status).opacity(0.12))
            .clipShape(Capsule())
    }
}

struct RequestUrgencyChip: View {
    let urgency: HelpRequestUrgency

    var body: some View {
        Label(urgency.title, systemImage: "exclamationmark.triangle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(RequestUI.urgencyColor(urgency))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RequestUI.urgencyColor(urgency).opacity(0.12))
            .clipShape(Capsule())
    }
}

struct RequestErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
    }
}

struct RequestInfoBanner: View {
    let message: String
    let color: Color

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
    }
}

struct RequestPrimaryButton: View {
    let title: String
    let systemImage: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: systemImage)
                    Text(title)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isLoading)
    }
}

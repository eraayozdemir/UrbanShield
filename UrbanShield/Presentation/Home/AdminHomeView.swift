//
//  AdminHomeView.swift
//  UrbanShield
//

import SwiftUI

/// Phase 1 placeholder — will be expanded in later phases.
struct AdminHomeView: View {
    let sessionViewModel: AuthSessionViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 64))
                    .foregroundStyle(.purple)

                Text("Admin Dashboard")
                    .font(.title2.bold())

                Text("Phase 2 features coming soon.")
                    .foregroundStyle(.secondary)

                Spacer()

                Button(role: .destructive) {
                    Task { await sessionViewModel.signOut() }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .padding()
            .navigationTitle("UrbanShield")
        }
    }
}

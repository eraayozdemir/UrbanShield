//
//  CoordinatorHomeView.swift
//  UrbanShield
//

import SwiftUI

struct CoordinatorHomeView: View {
    let sessionViewModel: AuthSessionViewModel

    var body: some View {
        NavigationStack {
            CoordinatorDashboardView(sessionViewModel: sessionViewModel)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            Task { await sessionViewModel.signOut() }
                        } label: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                        }
                        .tint(.red)
                    }
                }
        }
    }
}

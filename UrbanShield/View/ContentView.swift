//
//  ContentView.swift
//  UrbanShield
//
//  Eray tarafından 4.04.2026 tarihinde oluşturuldu.
//

import SwiftUI

// Eski template view. Gerçek uygulama UrbanShieldApp -> RootView üzerinden başlar.
// Bu dosya gerçek uygulama navigasyon akışında kullanılmaz.
struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

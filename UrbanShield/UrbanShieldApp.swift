//
//  UrbanShieldApp.swift
//  UrbanShield
//
//  Created by Eray on 4.04.2026.
//

import SwiftUI
import Supabase

@main
struct UrbanShieldApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.supabaseClient, supabase)
        }
    }
}

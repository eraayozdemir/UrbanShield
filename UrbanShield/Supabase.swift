//
//  Supabase.swift
//  UrbanShield
//
//  Created by Eray on 16.04.2026.
//

import Supabase

/// Uygulama genelinde tek bir Supabase client instance'ı.
/// Kullanım: `supabase.auth`, `supabase.database`, `supabase.storage` vb.
let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://coaruosbtrauskrehlzv.supabase.co")!,
    supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNvYXJ1b3NidHJhdXNrcmVobHp2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYzNDI3NzgsImV4cCI6MjA5MTkxODc3OH0.GbJZtNdCvJjfkp8h4FtX7JI8CMRT5GWUSlL8PjhZupE"
)

//
//  SupabaseManager.swift
//  UrbanShield
//

import Foundation
import Supabase

/// Genel Supabase client örneği.
/// `supabase.auth`, `supabase.from(...)`, `supabase.storage` vb. üzerinden erişilir.
///
/// ÖNEMLİ: Bu değerleri kendi Supabase projenizdeki değerlerle değiştirin:
///    Supabase Dashboard -> Settings -> API
let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://coaruosbtrauskrehlzv.supabase.co")!,
    supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNvYXJ1b3NidHJhdXNrcmVobHp2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYzNDI3NzgsImV4cCI6MjA5MTkxODc3OH0.GbJZtNdCvJjfkp8h4FtX7JI8CMRT5GWUSlL8PjhZupE"
)


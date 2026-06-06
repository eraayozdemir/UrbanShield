//
//  OfflineCacheStore.swift
//  UrbanShield
//

import Foundation

enum OfflineCacheStore {
    // Hafif demo/offline yedek akışı. Seçili request liste/detay verilerini
    // UserDefaults içinde saklar; böylece ağ hatasında ekranlar son bilinen veriyi gösterebilir.
    private static let prefix = "urbanshield.offline-cache."

    static func save<T: Codable>(_ value: T, forKey key: String) {
        do {
            let envelope = OfflineCacheEnvelope(savedAt: Date(), value: value)
            let data = try JSONEncoder.urbanShieldCacheEncoder.encode(envelope)
            UserDefaults.standard.set(data, forKey: prefix + key)
        } catch {
            UserDefaults.standard.removeObject(forKey: prefix + key)
        }
    }

    static func load<T: Codable>(_ type: T.Type, forKey key: String) -> OfflineCacheResult<T>? {
        // Kayıtlı değer yoksa veya decode başarısız olursa nil döndürür.
        guard let data = UserDefaults.standard.data(forKey: prefix + key),
              let envelope = try? JSONDecoder.urbanShieldCacheDecoder.decode(OfflineCacheEnvelope<T>.self, from: data) else {
            return nil
        }

        return OfflineCacheResult(value: envelope.value, savedAt: envelope.savedAt)
    }

    static func removeValue(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: prefix + key)
    }
}

struct OfflineCacheResult<T> {
    let value: T
    let savedAt: Date
}

private struct OfflineCacheEnvelope<T: Codable>: Codable {
    let savedAt: Date
    let value: T
}

private extension JSONEncoder {
    static var urbanShieldCacheEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var urbanShieldCacheDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

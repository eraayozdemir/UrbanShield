//
//  RealtimeRefreshSubscription.swift
//  UrbanShield
//

import Foundation
import Supabase

struct RealtimePostgresChangeRegistration {
    // Bir ekranın dinlediği Postgres tablo/filter çiftini tanımlar.
    let table: String
    let filter: String?

    init(table: String, filter: String? = nil) {
        self.table = table
        self.filter = filter
    }
}

@MainActor
final class RealtimeRefreshSubscription {
    // Near-realtime refresh ihtiyacı olan ekranlar için ortak yardımcı.
    // Row payload verisini parse etmez; yalnızca ekranın load metodunu
    // küçük bir throttle gecikmesinden sonra çağırır.
    private let throttleDelay: UInt64
    private var channel: RealtimeChannelV2?
    private var refreshTask: Task<Void, Never>?
    private var refresh: (() async -> Void)?

    init(throttleDelay: UInt64 = 1_200_000_000) {
        self.throttleDelay = throttleDelay
    }

    func start(
        channelName: String,
        registrations: [RealtimePostgresChangeRegistration],
        refresh: @escaping () async -> Void
    ) async throws {
        await stop()

        self.refresh = refresh

        let channel = supabase.channel(channelName)
        for registration in registrations {
            // Kayıtlı tabloda yapılan herhangi bir insert/update/delete refresh planlar.
            channel.onPostgresChange(
                AnyAction.self,
                table: registration.table,
                filter: registration.filter
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleRefresh()
                }
            }
        }

        try await channel.subscribeWithError()
        self.channel = channel
    }

    func stop() async {
        refreshTask?.cancel()
        refreshTask = nil
        refresh = nil

        if let channel {
            await supabase.removeChannel(channel)
            self.channel = nil
        }
    }

    private func scheduleRefresh() {
        // Throttling, kısa sürede gelen birden fazla database eventinin
        // birden fazla duplicate reload tetiklemesini engeller.
        guard refreshTask == nil else { return }

        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(nanoseconds: throttleDelay)
            } catch {
                refreshTask = nil
                return
            }

            guard !Task.isCancelled else {
                refreshTask = nil
                return
            }

            await refresh?()
            refreshTask = nil
        }
    }
}

//
//  NearbyRequestsView.swift
//  UrbanShield
//

import MapKit
import SwiftUI

struct NearbyRequestsView: View {
    let sessionViewModel: AuthSessionViewModel

    @State private var viewModel = NearbyRequestsViewModel()
    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @State private var radiusText = "10"
    @State private var isShowingMapPicker = false

    private var currentUser: User? {
        if case .authenticated(let user) = sessionViewModel.session {
            return user
        }
        return nil
    }

    private var filteredRequests: [NearbyRequestItem] {
        let centerLatitude = Double(latitudeText.replacingOccurrences(of: ",", with: "."))
        let centerLongitude = Double(longitudeText.replacingOccurrences(of: ",", with: "."))
        let radius = Double(radiusText.replacingOccurrences(of: ",", with: ".")) ?? 10

        return viewModel.requests.compactMap { request in
            guard let centerLatitude, let centerLongitude else {
                return NearbyRequestItem(request: request, distance: nil)
            }

            let distance = request.distanceInKilometers(fromLatitude: centerLatitude, longitude: centerLongitude)
            guard distance <= radius else { return nil }
            return NearbyRequestItem(request: request, distance: distance)
        }
        .sorted { lhs, rhs in
            switch (lhs.distance, rhs.distance) {
            case let (.some(left), .some(right)):
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.request.createdAt > rhs.request.createdAt
            }
        }
    }

    var body: some View {
        ZStack {
            RequestUI.background
                .ignoresSafeArea()

            if viewModel.isLoading && viewModel.requests.isEmpty {
                NearbyLoadingView(title: "Loading nearby requests...")
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        header
                            .padding(.top, 8)

                        locationFilter

                        if filteredRequests.isEmpty {
                            emptyState
                        } else {
                            ForEach(filteredRequests) { item in
                                NearbyRequestCard(
                                    item: item,
                                    isConfirming: viewModel.confirmingRequestId == item.request.id
                                ) {
                                    Task {
                                        let didConfirm = await viewModel.confirmRequest(
                                            item.request,
                                            volunteerId: currentUser?.id
                                        )
                                        if didConfirm {
                                            await sessionViewModel.refreshCurrentUser()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 18)
                }
                .refreshable {
                    await viewModel.loadOpenRequests(currentUserId: currentUser?.id)
                }
            }
        }
        .navigationTitle("Nearby Requests")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.loadOpenRequests(currentUserId: currentUser?.id)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .overlay(alignment: .bottom) {
            if let message = viewModel.errorMessage {
                RequestErrorBanner(message: message)
            } else if let message = viewModel.successMessage {
                RequestInfoBanner(message: message, color: .green)
            }
        }
        .task {
            await viewModel.loadOpenRequests(currentUserId: currentUser?.id)
        }
        .sheet(isPresented: $isShowingMapPicker) {
            MapCoordinatePickerView(
                title: "Pick Search Center",
                initialCoordinate: CLLocationCoordinate2D.urbanShieldParse(
                    latitude: latitudeText,
                    longitude: longitudeText
                )
            ) { coordinate in
                latitudeText = coordinate.urbanShieldLatitudeText
                longitudeText = coordinate.urbanShieldLongitudeText
            }
        }
    }

    private var header: some View {
        RequestCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Help near your area")
                        .font(.title3.bold())

                    Text("Confirm an open request to become the assigned volunteer. Confirmed tasks move to your volunteer dashboard.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var locationFilter: some View {
        RequestCard {
            HStack {
                RequestSectionTitle(title: "Area Filter", systemImage: "location.viewfinder")
                Spacer()
                Button {
                    isShowingMapPicker = true
                } label: {
                    Label("Pick Center", systemImage: "map.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }

            NearbyMapPreview(
                coordinate: CLLocationCoordinate2D.urbanShieldParse(
                    latitude: latitudeText,
                    longitude: longitudeText
                ),
                visibleCount: filteredRequests.count
            )

            HStack(spacing: 10) {
                RequestSmallTextField(title: "Latitude", text: $latitudeText)
                RequestSmallTextField(title: "Longitude", text: $longitudeText)
                RequestSmallTextField(title: "KM", text: $radiusText)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Open Requests",
            systemImage: "checkmark.shield",
            description: Text("There are no open requests matching this area right now.")
        )
        .padding(.vertical, 40)
    }
}

private struct NearbyRequestItem: Identifiable {
    let request: HelpRequestRecord
    let distance: Double?

    var id: UUID { request.id }
}

private struct NearbyMapPreview: View {
    let coordinate: CLLocationCoordinate2D?
    let visibleCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: coordinate == nil ? "location.magnifyingglass" : "scope")
                .font(.title3)
                .foregroundStyle(coordinate == nil ? Color.secondary : Color.green)
                .frame(width: 40, height: 40)
                .background((coordinate == nil ? Color.secondary : Color.green).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(coordinate == nil ? "Showing all open requests" : "\(visibleCount) request(s) in this area")
                    .font(.headline)

                Text(coordinateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var coordinateText: String {
        guard let coordinate else {
            return "Pick a center on the map or enter coordinates manually."
        }

        return "\(coordinate.urbanShieldLatitudeText), \(coordinate.urbanShieldLongitudeText)"
    }
}

private struct NearbyRequestCard: View {
    let item: NearbyRequestItem
    let isConfirming: Bool
    let onConfirm: () -> Void

    var body: some View {
        RequestCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: RequestUI.requestIcon(item.request.requestTypeValue))
                    .font(.headline)
                    .foregroundStyle(RequestUI.urgencyColor(item.request.urgencyValue))
                    .frame(width: 42, height: 42)
                    .background(RequestUI.urgencyColor(item.request.urgencyValue).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.request.requestTypeValue.title)
                        .font(.headline)

                    Text(item.request.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                RequestUrgencyChip(urgency: item.request.urgencyValue)
            }

            Text(item.request.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 8) {
                NearbyMetaPill(title: coordinateText, systemImage: "location.fill")

                if let distance = item.distance {
                    NearbyMetaPill(
                        title: "\(distance.formatted(.number.precision(.fractionLength(1)))) km",
                        systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                    )
                }

                Spacer()
            }

            Button(action: onConfirm) {
                HStack(spacing: 8) {
                    if isConfirming {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.shield.fill")
                        Text("Confirm as Volunteer")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isConfirming)
        }
    }

    private var coordinateText: String {
        let latitude = item.request.latitude.formatted(.number.precision(.fractionLength(2...4)))
        let longitude = item.request.longitude.formatted(.number.precision(.fractionLength(2...4)))
        return "\(latitude), \(longitude)"
    }
}

private struct RequestSmallTextField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(title, text: $text)
                .keyboardType(.decimalPad)
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 10)
                .frame(height: 42)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct NearbyMetaPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(Capsule())
    }
}

private struct NearbyLoadingView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension HelpRequestRecord {
    func distanceInKilometers(fromLatitude latitude: Double, longitude: Double) -> Double {
        let earthRadius = 6_371.0
        let lat1 = self.latitude * .pi / 180
        let lat2 = latitude * .pi / 180
        let deltaLat = (latitude - self.latitude) * .pi / 180
        let deltaLon = (longitude - self.longitude) * .pi / 180

        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2)
            * sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return earthRadius * c
    }
}

//
//  CoordinatorMapView.swift
//  UrbanShield
//

import Combine
import MapKit
import SwiftUI

struct CoordinatorMapView: View {
    let sessionViewModel: AuthSessionViewModel

    @State private var viewModel = CoordinatorMapViewModel()
    @StateObject private var locationService = DeviceLocationService()
    @State private var isShowingMapPicker = false
    @State private var shouldOverwriteWithCurrentLocation = false

    private var currentUser: User? {
        if case .authenticated(let user) = sessionViewModel.session {
            return user
        }
        return nil
    }

    var body: some View {
        ZStack {
            RequestUI.background
                .ignoresSafeArea()

            if viewModel.isLoading && viewModel.requests.isEmpty {
                CoordinatorMapLoadingView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        header
                            .padding(.top, 8)

                        CoordinatorOperationalMap(
                            requests: viewModel.filteredRequests,
                            centerCoordinate: CLLocationCoordinate2D.urbanShieldParse(
                                latitude: viewModel.latitudeText,
                                longitude: viewModel.longitudeText
                            )
                        )

                        filtersCard

                        requestResults
                    }
                    .padding(16)
                    .padding(.bottom, 18)
                }
                .refreshable {
                    await reloadMap()
                }
            }
        }
        .navigationTitle("Map")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await reloadMap() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .overlay(alignment: .bottom) {
            if let error = viewModel.errorMessage {
                RequestErrorBanner(message: error)
            }
        }
        .task {
            await reloadMap()
            if viewModel.latitudeText.isEmpty && viewModel.longitudeText.isEmpty {
                locationService.requestCurrentLocation()
            }
        }
        .onReceive(locationService.$coordinate.compactMap { $0 }) { coordinate in
            applyCurrentLocation(coordinate, overwritingManualInput: shouldOverwriteWithCurrentLocation)
            shouldOverwriteWithCurrentLocation = false
        }
        .sheet(isPresented: $isShowingMapPicker) {
            MapCoordinatePickerView(
                title: "Pick Map Center",
                initialCoordinate: CLLocationCoordinate2D.urbanShieldParse(
                    latitude: viewModel.latitudeText,
                    longitude: viewModel.longitudeText
                )
            ) { coordinate in
                viewModel.latitudeText = coordinate.urbanShieldLatitudeText
                viewModel.longitudeText = coordinate.urbanShieldLongitudeText
            }
        }
    }

    private func reloadMap() async {
        await viewModel.loadRequests(currentUser: currentUser)
    }

    private func applyCurrentLocation(
        _ coordinate: CLLocationCoordinate2D,
        overwritingManualInput: Bool
    ) {
        let shouldApply = overwritingManualInput || (viewModel.latitudeText.isEmpty && viewModel.longitudeText.isEmpty)
        guard shouldApply else { return }

        viewModel.latitudeText = coordinate.urbanShieldLatitudeText
        viewModel.longitudeText = coordinate.urbanShieldLongitudeText
    }

    private var header: some View {
        RequestCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "map.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Operational Map")
                        .font(.title2.bold())

                    Text("Filter requests by status, urgency, priority, type, text, and distance from a selected center.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var filtersCard: some View {
        RequestCard {
            HStack {
                RequestSectionTitle(title: "Advanced Filters", systemImage: "line.3.horizontal.decrease.circle.fill")
                Spacer()
                Button("Clear") {
                    withAnimation(.snappy(duration: 0.18)) {
                        viewModel.clearFilters()
                    }
                }
                .font(.subheadline.weight(.semibold))
            }

            TextField("Search request text, type, status, urgency", text: $viewModel.searchText)
                .textInputAutocapitalization(.never)
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatusFilterMenu(selection: $viewModel.statusFilter)
                UrgencyFilterMenu(selection: $viewModel.urgencyFilter)
                TypeFilterMenu(selection: $viewModel.typeFilter)
                PriorityFilterMenu(selection: $viewModel.priorityFilter)
            }

            HStack {
                RequestSectionTitle(title: "Search Center", systemImage: "scope")
                Spacer()
                Button {
                    shouldOverwriteWithCurrentLocation = true
                    locationService.requestCurrentLocation()
                } label: {
                    if locationService.isRequestingLocation {
                        ProgressView()
                    } else {
                        Label("Current", systemImage: "location.fill.viewfinder")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .buttonStyle(.bordered)

                Button {
                    isShowingMapPicker = true
                } label: {
                    Label("Pick", systemImage: "map.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                RequestSmallMapField(title: "Latitude", text: $viewModel.latitudeText)
                RequestSmallMapField(title: "Longitude", text: $viewModel.longitudeText)
                RequestSmallMapField(title: "KM", text: $viewModel.radiusText)
            }

            if let locationError = locationService.errorMessage {
                Label(locationError, systemImage: "location.slash.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var requestResults: some View {
        RequestCard {
            HStack {
                RequestSectionTitle(title: "Filtered Requests", systemImage: "list.bullet.rectangle.fill")
                Spacer()
                Text("\(viewModel.filteredRequests.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if viewModel.filteredRequests.isEmpty {
                MapEmptyRow(title: "No requests match the current filters.", systemImage: "map")
            } else {
                ForEach(viewModel.filteredRequests.prefix(12)) { request in
                    NavigationLink {
                        RequestDetailView(
                            requestId: request.id,
                            sessionViewModel: sessionViewModel
                        )
                    } label: {
                        CoordinatorMapRequestRow(request: request)
                    }
                    .buttonStyle(.plain)

                    if request.id != viewModel.filteredRequests.prefix(12).last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct CoordinatorOperationalMap: View {
    let requests: [HelpRequestRecord]
    let centerCoordinate: CLLocationCoordinate2D?

    @State private var cameraPosition: MapCameraPosition

    init(requests: [HelpRequestRecord], centerCoordinate: CLLocationCoordinate2D?) {
        self.requests = requests
        self.centerCoordinate = centerCoordinate
        _cameraPosition = State(initialValue: .region(Self.region(for: centerCoordinate, requests: requests)))
    }

    var body: some View {
        Map(position: $cameraPosition) {
            if let centerCoordinate {
                Marker("Search center", systemImage: "scope", coordinate: centerCoordinate)
                    .tint(.blue)
            }

            ForEach(requests) { request in
                Marker(
                    request.requestTypeValue.title,
                    systemImage: RequestUI.requestIcon(request.requestTypeValue),
                    coordinate: request.operationalCoordinate
                )
                .tint(RequestUI.priorityColor(request.priorityValue))
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topLeading) {
            Text("\(requests.count) request pin(s)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial)
                .clipShape(Capsule())
                .padding(10)
        }
        .onChange(of: cameraKey) {
            cameraPosition = .region(Self.region(for: centerCoordinate, requests: requests))
        }
    }

    private var cameraKey: String {
        let centerKey = centerCoordinate.map { "\($0.latitude),\($0.longitude)" } ?? "none"
        let requestKey = requests.map { $0.id.uuidString }.joined(separator: ",")
        return "\(centerKey)-\(requestKey)"
    }

    private static func region(
        for centerCoordinate: CLLocationCoordinate2D?,
        requests: [HelpRequestRecord]
    ) -> MKCoordinateRegion {
        if let centerCoordinate {
            return MKCoordinateRegion(
                center: centerCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
            )
        }

        if let first = requests.first {
            return MKCoordinateRegion(
                center: first.operationalCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
            )
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784),
            span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
        )
    }
}

private struct CoordinatorMapRequestRow: View {
    let request: HelpRequestRecord

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: RequestUI.requestIcon(request.requestTypeValue))
                .font(.subheadline)
                .foregroundStyle(RequestUI.priorityColor(request.priorityValue))
                .frame(width: 34, height: 34)
                .background(RequestUI.priorityColor(request.priorityValue).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(request.requestTypeValue.title)
                    .font(.subheadline.weight(.semibold))

                Text(request.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    RequestStatusChip(status: request.statusValue)
                    RequestPriorityChip(priority: request.priorityValue)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }
}

private struct StatusFilterMenu: View {
    @Binding var selection: HelpRequestStatus?

    var body: some View {
        OperationalFilterMenu(
            title: "Status",
            value: selection?.title ?? "All",
            systemImage: "checklist"
        ) {
            Button("All") { selection = nil }
            ForEach(HelpRequestStatus.allCases) { status in
                Button(status.title) { selection = status }
            }
        }
    }
}

private struct UrgencyFilterMenu: View {
    @Binding var selection: HelpRequestUrgency?

    var body: some View {
        OperationalFilterMenu(
            title: "Urgency",
            value: selection?.title ?? "All",
            systemImage: "exclamationmark.triangle.fill"
        ) {
            Button("All") { selection = nil }
            ForEach(HelpRequestUrgency.allCases) { urgency in
                Button(urgency.title) { selection = urgency }
            }
        }
    }
}

private struct TypeFilterMenu: View {
    @Binding var selection: HelpRequestType?

    var body: some View {
        OperationalFilterMenu(
            title: "Type",
            value: selection?.title ?? "All",
            systemImage: "square.grid.2x2"
        ) {
            Button("All") { selection = nil }
            ForEach(HelpRequestType.allCases) { type in
                Button(type.title) { selection = type }
            }
        }
    }
}

private struct PriorityFilterMenu: View {
    @Binding var selection: HelpRequestPriority?

    var body: some View {
        OperationalFilterMenu(
            title: "Priority",
            value: selection?.title ?? "All",
            systemImage: "flag.fill"
        ) {
            Button("All") { selection = nil }
            ForEach(HelpRequestPriority.allCases) { priority in
                Button(priority.title) { selection = priority }
            }
        }
    }
}

private struct OperationalFilterMenu<Content: View>: View {
    let title: String
    let value: String
    let systemImage: String
    let content: Content

    init(
        title: String,
        value: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 28, height: 28)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(value)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct RequestSmallMapField: View {
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

private struct MapEmptyRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }
}

private struct CoordinatorMapLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading operational map...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension HelpRequestRecord {
    var operationalCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

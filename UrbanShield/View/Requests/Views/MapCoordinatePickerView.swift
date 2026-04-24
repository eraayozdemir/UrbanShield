//
//  MapCoordinatePickerView.swift
//  UrbanShield
//

import MapKit
import SwiftUI

struct MapCoordinatePickerView: View {
    let title: String
    let initialCoordinate: CLLocationCoordinate2D?
    let onSelect: (CLLocationCoordinate2D) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var cameraPosition: MapCameraPosition

    init(
        title: String,
        initialCoordinate: CLLocationCoordinate2D?,
        onSelect: @escaping (CLLocationCoordinate2D) -> Void
    ) {
        self.title = title
        self.initialCoordinate = initialCoordinate
        self.onSelect = onSelect

        let coordinate = initialCoordinate ?? CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784)
        _selectedCoordinate = State(initialValue: initialCoordinate)
        _cameraPosition = State(
            initialValue: .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
                )
            )
        )
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        if let selectedCoordinate {
                            Marker("Selected Location", coordinate: selectedCoordinate)
                                .tint(.red)
                        }
                    }
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                    }
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                if let coordinate = proxy.convert(value.location, from: .local) {
                                    selectedCoordinate = coordinate
                                }
                            }
                    )
                }
                .ignoresSafeArea(edges: .bottom)

                selectionPanel
                    .padding(16)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Use") {
                        if let selectedCoordinate {
                            onSelect(selectedCoordinate)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedCoordinate == nil)
                }
            }
        }
    }

    private var selectionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Tap the map to choose a coordinate")
                        .font(.headline)

                    Text(selectedCoordinateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }

    private var selectedCoordinateText: String {
        guard let selectedCoordinate else {
            return "No coordinate selected yet"
        }

        let latitude = selectedCoordinate.latitude.formatted(.number.precision(.fractionLength(5...6)))
        let longitude = selectedCoordinate.longitude.formatted(.number.precision(.fractionLength(5...6)))
        return "\(latitude), \(longitude)"
    }
}

extension CLLocationCoordinate2D {
    static func urbanShieldParse(latitude: String, longitude: String) -> CLLocationCoordinate2D? {
        guard let latitudeValue = Double(latitude.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")),
              let longitudeValue = Double(longitude.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")),
              (-90...90).contains(latitudeValue),
              (-180...180).contains(longitudeValue) else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: latitudeValue, longitude: longitudeValue)
    }

    var urbanShieldLatitudeText: String {
        latitude.formatted(.number.precision(.fractionLength(5...6)))
    }

    var urbanShieldLongitudeText: String {
        longitude.formatted(.number.precision(.fractionLength(5...6)))
    }
}

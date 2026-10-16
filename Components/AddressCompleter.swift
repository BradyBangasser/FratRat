//
//  AddressCompleter.swift
//  FratRat
//
//  Created by Brady Bangasser on 7/13/26.
//


//
//  AddressAutocompleteField.swift
//  FratRat
//
//  Proper address autocomplete for posting a party. Replaces the old
//  fire-a-full-MKLocalSearch-on-every-keystroke approach with
//  MKLocalSearchCompleter (Apple's real autocomplete: debounced, ranked, biased
//  to the user's area), plus a "Use current location" button that reverse-
//  geocodes the device location into a pickable address.
//
//  Uses Apple's on-device/Maps services only — no FratRat backend, no identity —
//  so this is the same architectural category as the existing map/search code.
//

import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - Completer

/// Thin ObservableObject wrapper around MKLocalSearchCompleter.
@MainActor
final class AddressCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var suggestions: [MKLocalSearchCompletion] = []
    @Published var isResolving = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    /// Bias results toward the user so "215 Lynn" finds the one on campus.
    func biasRegion(around location: CLLocation?) {
        guard let location else { return }
        completer.region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)
        )
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            suggestions = []
            completer.queryFragment = ""
            return
        }
        completer.queryFragment = trimmed
    }

    func clear() {
        suggestions = []
        completer.queryFragment = ""
    }

    /// Resolve a tapped suggestion into a concrete MKMapItem (with coordinate).
    func resolve(_ completion: MKLocalSearchCompletion) async -> MKMapItem? {
        isResolving = true
        defer { isResolving = false }
        let request = MKLocalSearch.Request(completion: completion)
        return try? await MKLocalSearch(request: request).start().mapItems.first
    }

    // Delegate
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in self.suggestions = Array(results.prefix(5)) }
    }
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.suggestions = [] }
    }
}

// MARK: - Field

struct AddressAutocompleteField: View {
    @Binding var address: String
    @Binding var selectedItem: MKMapItem?
    var userLocation: CLLocation?

    @StateObject private var completer = AddressCompleter()
    @FocusState private var focused: Bool
    @State private var reverseGeocoding = false
    @State private var geocodeFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Field row
            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 15))
                    .foregroundColor(selectedItem != nil ? .green : .fratGray)

                TextField("Search address or venue…", text: $address)
                    .font(.fratBody(15))
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.search)
                    .onChange(of: address) { _, newValue in
                        // Typing invalidates a previously-picked location.
                        if selectedItem != nil { selectedItem = nil }
                        geocodeFailed = false
                        completer.update(query: newValue)
                    }

                if selectedItem != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .transition(.scale.combined(with: .opacity))
                } else if !address.isEmpty {
                    Button {
                        address = ""
                        completer.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.fratGray.opacity(0.5))
                    }
                    .accessibilityLabel("Clear address")
                }
            }

            // Current-location button
            Button {
                Task { await useCurrentLocation() }
            } label: {
                HStack(spacing: 8) {
                    if reverseGeocoding {
                        ProgressView().scaleEffect(0.8).tint(.fratPink)
                    } else {
                        Image(systemName: "location.fill").font(.system(size: 13))
                    }
                    Text(reverseGeocoding ? "Finding you…" : "Use current location")
                        .font(.fratSemi(13))
                }
                .foregroundColor(.fratPink)
                .padding(.vertical, 8)
            }
            .disabled(reverseGeocoding)
            .padding(.top, 6)

            if geocodeFailed {
                FieldErrorText(text: "Couldn't pin your location. Search for the address instead.")
                    .padding(.top, 2)
            }

            // Suggestions
            if !completer.suggestions.isEmpty && focused {
                Divider().padding(.vertical, 8)
                VStack(spacing: 0) {
                    ForEach(completer.suggestions, id: \.self) { suggestion in
                        Button {
                            Task { await pick(suggestion) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundColor(.fratPink)
                                    .font(.system(size: 16))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title)
                                        .font(.fratSemi(14))
                                        .foregroundColor(.fratDark)
                                        .lineLimit(1)
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle)
                                            .font(.fratBody(12))
                                            .foregroundColor(.fratGray)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                        if suggestion != completer.suggestions.last {
                            Divider().padding(.leading, 26)
                        }
                    }
                }
            }
        }
        .onAppear { completer.biasRegion(around: userLocation) }
        .onChange(of: userLocation) { _, loc in completer.biasRegion(around: loc) }
        .animation(.easeInOut(duration: 0.15), value: selectedItem != nil)
    }

    // MARK: - Actions

    private func pick(_ suggestion: MKLocalSearchCompletion) async {
        focused = false
        if let item = await completer.resolve(suggestion) {
            selectedItem = item
            address = [suggestion.title, suggestion.subtitle]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            completer.clear()
        }
    }

    private func useCurrentLocation() async {
        guard let loc = userLocation else { geocodeFailed = true; return }
        focused = false
        reverseGeocoding = true
        geocodeFailed = false
        defer { reverseGeocoding = false }

        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(loc)
        guard let placemark = placemarks?.first else { geocodeFailed = true; return }

        let mkPlacemark = MKPlacemark(placemark: placemark)
        let item = MKMapItem(placemark: mkPlacemark)
        item.name = placemark.name
        selectedItem = item
        address = [placemark.name, placemark.locality]
            .compactMap { $0 }
            .joined(separator: ", ")
        completer.clear()
    }
}

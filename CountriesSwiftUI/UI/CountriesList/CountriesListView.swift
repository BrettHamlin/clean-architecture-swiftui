//
//  CountriesList.swift
//  CountriesSwiftUI
//
//  Created by Alexey on 7/11/24.
//  Copyright © 2024 Alexey Naumov. All rights reserved.
//

import SwiftUI
import SwiftData
import Combine
import Foundation

struct CountriesList: View {

    @State private var countries: [DBModel.Country] = []
    @State private(set) var countriesState: Loadable<Void>
    @State private var canRequestPushPermission: Bool = false
    @State internal var searchText = ""
    @State internal var showFavoritesOnly: Bool = false
    @State internal var navigationPath = NavigationPath()
    @State private var routingState: Routing = .init()
    @State private var routedCountryCode: String?
    private var routingBinding: Binding<Routing> {
        $routingState.dispatched(to: injected.appState, \.routing.countriesList)
    }
    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.locale) private var locale: Locale
    private let localeContainer = LocaleReader.Container()

    let inspection = Inspection<Self>()

    init(state: Loadable<Void> = .notRequested) {
        self._countriesState = .init(initialValue: state)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            content
                .query(searchText: searchText, showFavoritesOnly: showFavoritesOnly, results: $countries, { search, favoritesOnly in
                    Query(filter: #Predicate<DBModel.Country> { country in
                        (!favoritesOnly || country.isFavorite)
                            && (search.isEmpty || country.name.localizedStandardContains(search))
                    }, sort: \DBModel.Country.name)
                })
                .navigationTitle("Countries")
        }
        .modifier(LocaleReader(container: localeContainer))
        .onReceive(routingUpdate) { self.routingState = $0 }
        .onReceive(canRequestPushPermissionUpdate) { self.canRequestPushPermission = $0 }
        .onReceive(inspection.notice) { self.inspection.visit(self, $0) }
        .flipsForRightToLeftLayoutDirection(true)
    }

    @ViewBuilder private var content: some View {
        switch countriesState {
        case .notRequested:
            defaultView()
        case .isLoading:
            loadingView()
        case .loaded:
            loadedView()
        case let .failed(error):
            failedView(error)
        }
    }

    @ViewBuilder private var permissionsButton: some View {
        if canRequestPushPermission {
            Button(action: requestPushPermission, label: { Text("Allow Push") })
        }
    }

    private var favoritesFilterButton: some View {
        Button(action: toggleFavoritesFilter) {
            Label("Show Favorites", systemImage: showFavoritesOnly ? "star.fill" : "star")
        }
        .accessibilityIdentifier("showFavoritesOnlyButton")
    }
}

// MARK: - Loading Content

private extension CountriesList {
    func defaultView() -> some View {
        Text("").onAppear {
            if !countries.isEmpty {
                countriesState = .loaded(())
            }
            loadCountriesList(forceReload: false)
        }
    }

    func loadingView() -> some View {
        ProgressView()
            .progressViewStyle(CircularProgressViewStyle())
    }

    func failedView(_ error: Error) -> some View {
        ErrorView(error: error, retryAction: {
            loadCountriesList(forceReload: true)
        })
    }
}

// MARK: - Displaying Content

@MainActor
private extension CountriesList {
    @ViewBuilder
    func loadedView() -> some View {
        if countries.isEmpty && !searchText.isEmpty {
            Text("No matches found")
                .font(.footnote)
        }
        List(countries, id: \.alpha3Code) { country in
            NavigationLink(value: country) {
                CountryCell(country: country)
            }
        }
        .navigationDestination(for: DBModel.Country.self) { country in
            CountryDetails(country: country)
        }
        .searchable(text: $searchText)
        .refreshable {
            loadCountriesList(forceReload: true)
        }
        .toolbar {
            ToolbarItem {
                favoritesFilterButton
            }
            ToolbarItem {
                permissionsButton
            }
        }
        .onChange(of: routingState.countryCode, initial: true, { _, code in
            routeToCountry(code: code)
        })
        .onChange(of: countries.map(\.alpha3Code), initial: true, { _, _ in
            routeToCountry(code: routingState.countryCode)
        })
        .onChange(of: navigationPath, { _, path in
            if !path.isEmpty {
                routingBinding.wrappedValue.countryCode = nil
            } else {
                routedCountryCode = nil
            }
        })
    }
}

// MARK: - Side Effects

private extension CountriesList {

    private func loadCountriesList(forceReload: Bool) {
        guard forceReload || countries.isEmpty else { return }
        $countriesState.load {
            try await injected.interactors.countries
                .refreshCountriesList()
        }
    }

    private func requestPushPermission() {
        injected.interactors.userPermissions
            .request(permission: .pushNotifications)
    }

    private func toggleFavoritesFilter() {
        showFavoritesOnly.toggle()
    }

    @MainActor
    private func routeToCountry(code: String?) {
        guard let code, routedCountryCode != code else { return }
        if let country = countries.first(where: { $0.alpha3Code == code }) {
            routedCountryCode = code
            navigationPath.append(country)
        } else if showFavoritesOnly {
            showFavoritesOnly = false
        }
    }
}

// MARK: - Routing

extension CountriesList {
    struct Routing: Equatable {
        var countryCode: String?
    }
}

// MARK: - State Updates

private extension CountriesList {

    private var routingUpdate: AnyPublisher<Routing, Never> {
        injected.appState.updates(for: \.routing.countriesList)
    }

    private var canRequestPushPermissionUpdate: AnyPublisher<Bool, Never> {
        injected.appState.updates(for: AppState.permissionKeyPath(for: .pushNotifications))
            .map { $0 == .notRequested || $0 == .denied }
            .eraseToAnyPublisher()
    }
}

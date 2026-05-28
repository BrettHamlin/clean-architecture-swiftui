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

struct CountriesList: View {

    @State private var countries: [DBModel.Country] = []
    @State private(set) var countriesState: Loadable<Void>
    @State private var canRequestPushPermission: Bool = false
    @State internal var searchText = ""
    @State internal var navigationPath = NavigationPath()
    @State internal var sortOrder: SortOrder = .alphabetical
    @State private var routingState: Routing = .init()
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
                .query(searchText: searchText, results: $countries, sortOrder: sortOrder) { search, sortOrder in
                    Query(filter: #Predicate<DBModel.Country> { country in
                        if search.isEmpty {
                            return true
                        } else {
                            return country.name.localizedStandardContains(search)
                        }
                    }, sort: sortOrder.sortDescriptors)
                }
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
                Button(action: toggleSortOrder, label: {
                    Text(sortOrder.buttonTitle)
                })
            }
            ToolbarItem {
                permissionsButton
            }
        }
        .onChange(of: routingState.countryCode, initial: true, { _, code in
            guard let code,
                  let country = countries.first(where: { $0.alpha3Code == code})
            else { return }
            navigationPath.append(country)
        })
        .onChange(of: navigationPath, { _, path in
            if !path.isEmpty {
                routingBinding.wrappedValue.countryCode = nil
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

    private func toggleSortOrder() {
        sortOrder.toggle()
    }
}

// MARK: - Routing

extension CountriesList {
    enum SortOrder: Equatable {
        case alphabetical
        case byPopulation

        var sortDescriptors: [SortDescriptor<DBModel.Country>] {
            switch self {
            case .alphabetical:
                return [SortDescriptor(\DBModel.Country.name)]
            case .byPopulation:
                return [SortDescriptor(\DBModel.Country.population, order: .reverse)]
            }
        }

        var buttonTitle: String {
            switch self {
            case .alphabetical:
                return "Sort by Population"
            case .byPopulation:
                return "Sort Alphabetically"
            }
        }

        mutating func toggle() {
            switch self {
            case .alphabetical:
                self = .byPopulation
            case .byPopulation:
                self = .alphabetical
            }
        }
    }

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

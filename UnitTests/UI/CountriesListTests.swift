//
//  CountriesListTests.swift
//  UnitTests
//
//  Created by Alexey Naumov on 01.11.2019.
//  Copyright © 2019 Alexey Naumov. All rights reserved.
//

import Testing
import ViewInspector
import SwiftData
import SwiftUI
import Foundation
@testable import CountriesSwiftUI

@MainActor
@Suite struct CountriesListTests {

    let apiCountries: [ApiModel.Country]
    let dbCountries: [DBModel.Country]

    init() {
        apiCountries = ApiModel.Country.mockedData
        dbCountries = apiCountries.map { $0.dbModel() }
    }

    @Test func noCachedCountries() async throws {
        let container = DIContainer(interactors: .mocked(countries: [
            .refreshCountriesList,
        ]))
        let sut = CountriesList(state: .notRequested)
        try await ViewHosting.host(sut.inject(container)) {
            try await sut.inspection.inspect { view in
                #expect(container.appState.value == AppState())
                container.interactors.verify()
            }
        }
    }

    @Test func cachedCountries() async throws {
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .notRequested)
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                #expect(container.appState.value == AppState())
                container.interactors.verify()
            }
        }
    }

    @Test func noMatchesWhenSearching() async throws {
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.actualView().searchText = "whatever"
            }
            try await sut.inspection.inspect { view in
                #expect(throws: Never.self) { try view.find(text: "No matches found") }
                container.interactors.verify()
            }
        }
    }

    @Test func listRefresh() async throws {
        let container = DIContainer(interactors: .mocked(countries: [
            .refreshCountriesList
        ]))
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let list = try view.find(ViewType.List.self)
                try await list.callRefreshable()
                container.interactors.verify()
            }
        }
    }

    @Test func countriesIsLoadingInitial() async throws {
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .isLoading(last: nil, cancelBag: .test))
        try await ViewHosting.host(sut.inject(container)) {
            try await sut.inspection.inspect { view in
                let content = try view.content()
                #expect(throws: Never.self) { try content.find(ViewType.ProgressView.self) }
                #expect(container.appState.value == AppState())
                container.interactors.verify()
            }
        }
    }

    @Test func countriesLoaded() async throws {
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)
        let firstRowCountry = try #require(dbCountries.sorted(by: { $0.name < $1.name }).first)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let content = try view.content()
                #expect(throws: (any Error).self) { try content.find(ViewType.ProgressView.self) }
                let cell = try content.find(CountryCell.self).actualView()
                #expect(cell.country.name == firstRowCountry.name)
                #expect(container.appState.value == AppState())
                container.interactors.verify()
            }
        }
    }

    // harness:criterion=c-sort-state-default-alphabetical,c-sort-mode-enum-two-cases
    @Test func sortModeDefaultsToAlphabeticalAndHasTwoCases() async throws {
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        try await ViewHosting.host(sut.inject(container)) {
            try await sut.inspection.inspect { view in
                let actualView = try view.actualView()
                #expect(actualView.sortMode == .alphabetical)
                #expect(actualView.sortMode != .byPopulation)
                #expect(CountriesList.SortMode.allCases == [.alphabetical, .byPopulation])
                container.interactors.verify()
            }
        }
    }

    // harness:criterion=c-sort-toggle-button-present,c-sort-toggle-button-does-not-displace-permissions-button
    @Test func toolbarContainsSortToggleAndPermissionsButton() async throws {
        let container = DIContainer(interactors: .mocked())
        container.appState[\.permissions.push] = .notRequested
        let sut = CountriesList(state: .loaded(()))
        let view = sut.inject(container)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let sortButton = try view.sortToggleButton()
                let sortTitle = try sortButton.labelView().find(ViewType.Text.self).string()
                let permissionsButton = try view.find(button: "Allow Push")
                let permissionsTitle = try permissionsButton.labelView().text().string()
                #expect(sortTitle == "Sort by Population")
                #expect(permissionsTitle == "Allow Push")
                container.interactors.verify()
            }
        }
    }

    // harness:criterion=c-sort-toggle-cycles-modes,c-search-text-state-preserved-on-sort-toggle,c-sort-toggle-does-not-trigger-interactor-refresh,c-sort-toggle-does-not-trigger-permission-call,c-sort-state-is-ephemeral
    @Test func sortToggleCyclesPreservesSearchAndHasNoSideEffects() async throws {
        let beforeDefaultsKeys = Set(UserDefaults.standard.dictionaryRepresentation().keys)
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.actualView().searchText = "Canada"
                let initialSearchText = try view.actualView().searchText
                try view.sortToggleButton().tap()
                let firstSortMode = try view.actualView().sortMode
                let firstSearchText = try view.actualView().searchText
                #expect(firstSortMode == .byPopulation)
                #expect(firstSearchText == initialSearchText)
                try view.sortToggleButton().tap()
                let secondSortMode = try view.actualView().sortMode
                let secondSearchText = try view.actualView().searchText
                #expect(secondSortMode == .alphabetical)
                #expect(secondSearchText == initialSearchText)
                #expect(container.appState.value == AppState())
                container.interactors.verify()
            }
        }
        let afterDefaultsKeys = Set(UserDefaults.standard.dictionaryRepresentation().keys)
        let newSortDefaultsKeys = afterDefaultsKeys.subtracting(beforeDefaultsKeys).filter {
            $0.localizedCaseInsensitiveContains("sort") ||
            $0.localizedCaseInsensitiveContains("countries")
        }
        #expect(newSortDefaultsKeys.isEmpty)
    }

    // harness:criterion=c-query-search-accepts-sort-mode,c-query-container-equality-includes-sort-mode
    @Test func queryContainerCarriesSortModeAndComparesItForEquality() throws {
        var capturedSortMode: CountriesList.SortMode?
        let byPopulation = QueryViewContainer<DBModel.Country, CountriesList.SortMode>(
            searchText: "an",
            sortMode: .byPopulation,
            builder: { searchText, sortMode in
                capturedSortMode = sortMode
                return CountriesList.query(searchText: searchText, sortMode: sortMode)
            },
            results: { _, _ in }
        )
        let alphabetical = QueryViewContainer<DBModel.Country, CountriesList.SortMode>(
            searchText: "an",
            sortMode: .alphabetical,
            builder: { searchText, sortMode in
                CountriesList.query(searchText: searchText, sortMode: sortMode)
            },
            results: { _, _ in }
        )

        _ = byPopulation.body

        #expect(capturedSortMode == .byPopulation)
        #expect(alphabetical != byPopulation)
    }

    // harness:criterion=c-alphabetical-sort-uses-name-ascending,c-population-sort-uses-population-descending,c-alphabetical-sort-descriptor-seam,c-population-sort-descriptor-seam
    @Test func queryResultsUseSelectedSortMode() async throws {
        let alphabetical = try await queryResults(searchText: "", sortMode: .alphabetical)
        let byPopulation = try await queryResults(searchText: "", sortMode: .byPopulation)
        let expectedAlphabeticalNames = apiCountries
            .sorted { $0.name < $1.name }
            .map(\.name)
        let expectedPopulationNames = apiCountries
            .sorted { $0.population > $1.population }
            .map(\.name)

        #expect(alphabetical.map(\.name) == expectedAlphabeticalNames)
        #expect(byPopulation.map(\.name) == expectedPopulationNames)
    }

    // harness:criterion=c-search-with-alphabetical-sort-filters-correctly,c-search-with-population-sort-filters-correctly
    @Test func querySearchFiltersResultsInBothSortModes() async throws {
        let searchText = "an"
        let expectedNames = apiCountries
            .filter { $0.name.localizedStandardContains(searchText) }
            .map(\.name)
            .sorted()

        let alphabetical = try await queryResults(searchText: searchText, sortMode: .alphabetical)
        let byPopulation = try await queryResults(searchText: searchText, sortMode: .byPopulation)

        #expect(alphabetical.map(\.name).sorted() == expectedNames)
        #expect(byPopulation.map(\.name).sorted() == expectedNames)
    }

    // harness:criterion=c-pull-to-refresh-unaffected-by-sort
    @Test func pullToRefreshWorksInEverySortMode() async throws {
        for sortMode in CountriesList.SortMode.allCases {
            let container = DIContainer(interactors: .mocked(countries: [
                .refreshCountriesList
            ]))
            let sut = CountriesList(state: .loaded(()))
            let modelContainer = ModelContainer.mock
            let dbRepository = MainDBRepository(modelContainer: modelContainer)
            try await dbRepository.store(countries: apiCountries)
            let view = sut.inject(container).modelContainer(modelContainer)
            try await ViewHosting.host(view) {
                try await sut.inspection.inspect { view in
                    try view.actualView().sortMode = sortMode
                    let list = try view.find(ViewType.List.self)
                    try await list.callRefreshable()
                    container.interactors.verify()
                }
            }
        }
    }

    // harness:criterion=c-navigationlink-routing-unaffected-by-sort
    @Test func deepLinkRoutingWorksInEverySortMode() async throws {
        for sortMode in CountriesList.SortMode.allCases {
            let store = Store(AppState())
            let container = DIContainer(appState: store, interactors: .mocked())
            let sut = CountriesList(state: .loaded(()))
            let modelContainer = ModelContainer.mock
            let dbRepository = MainDBRepository(modelContainer: modelContainer)
            try await dbRepository.store(countries: apiCountries)
            let view = sut.inject(container).modelContainer(modelContainer)
            try await ViewHosting.host(view) {
                try await sut.inspection.inspect { view in
                    try view.actualView().sortMode = sortMode
                }
                try await sut.inspection.inspect(after: .seconds(0.2)) { _ in
                    container.appState[\.routing.countriesList.countryCode] = "CAN"
                }
                try await sut.inspection.inspect(after: .seconds(0.2)) { view in
                    let actualView = try view.actualView()
                    #expect(!actualView.navigationPath.isEmpty)
                    container.interactors.verify()
                }
            }
        }
    }
    
    @Test func countriesFailed() async throws {
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .failed(NSError.test))
        try await ViewHosting.host(sut.inject(container)) {
            try await sut.inspection.inspect { view in
                #expect(throws: Never.self) { try view.content().implicitAnyView().implicitAnyView().implicitAnyView().view(ErrorView.self, 0) }
                #expect(container.appState.value == AppState())
                container.interactors.verify()
            }
        }
    }
    
    @Test func countriesFailedRetry() async throws {
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .failed(NSError.test))
        try await ViewHosting.host(sut.inject(container)) {
            try await sut.inspection.inspect { view in
                let errorView = try view.content().implicitAnyView().implicitAnyView().implicitAnyView().view(ErrorView.self, 0)
                try errorView.implicitAnyView().vStack().button(2).tap()
                #expect(container.appState.value == AppState())
                container.interactors.verify()
            }
        }
    }

    @Test func requestPush() async throws {
        let container = DIContainer(interactors: .mocked(permissions: [
            .request(.pushNotifications)
        ]))
        container.appState[\.permissions.push] = .notRequested
        let sut = CountriesList(state: .loaded(()))
        try await ViewHosting.host(sut.inject(container)) {
            try await sut.inspection.inspect { view in
                try view.find(button: "Allow Push").tap()
                container.interactors.verify()
            }
        }
    }

    private func queryResults(
        searchText: String,
        sortMode: CountriesList.SortMode
    ) async throws -> [DBModel.Country] {
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let sut = QueryProbe(searchText: searchText, sortMode: sortMode)
        var countries: [DBModel.Country] = []
        try await ViewHosting.host(sut.modelContainer(modelContainer)) {
            try await sut.inspection.inspect(after: .seconds(0.2)) { view in
                countries = try view.actualView().results
            }
        }
        return countries
    }
}

@Suite struct LocalizationTests {

    @Test func countryLocalizedName() {
        let sut = DBModel.Country(name: "Abc", translations: ["fr": "Xyz"], population: 0, flag: nil, alpha3Code: "")
        let locale = Locale(identifier: "fr")
        #expect(sut.name(locale: locale) == "Xyz")
    }
}

// MARK: - CountriesList inspection helper

extension InspectableView where View == ViewType.View<CountriesList> {
    func content() throws -> InspectableView<ViewType.NavigationStack> {
        return try implicitAnyView().navigationStack()
    }

    func sortToggleButton() throws -> InspectableView<ViewType.Button> {
        try find(ViewType.Button.self) { button in
            if (try? button.accessibilityIdentifier()) == "countries.sort.toggle" {
                return true
            }
            let label = try button.labelView()
            return (try? label.find(text: "Sort by Population")) != nil ||
                (try? label.find(text: "Sort Alphabetically")) != nil
        }
    }
}

// MARK: - Query inspection helper

private struct QueryProbe: View {
    let searchText: String
    let sortMode: CountriesList.SortMode
    @State var results: [DBModel.Country] = []

    let inspection = Inspection<Self>()

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .query(searchText: searchText, results: $results, sortMode: sortMode) { searchText, sortMode in
                CountriesList.query(searchText: searchText, sortMode: sortMode)
            }
            .onReceive(inspection.notice) { self.inspection.visit(self, $0) }
    }
}

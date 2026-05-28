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
        //harness:criterion=c-searchable-preserved
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
        //harness:criterion=c-refreshable-preserved
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

    @Test func sortOrderEnumExposesExpectedCases() {
        //harness:criterion=c-sort-order-enum-cases
        func title(for sortOrder: CountriesList.SortOrder) -> String {
            switch sortOrder {
            case .alphabetical:
                return "alphabetical"
            case .byPopulation:
                return "byPopulation"
            }
        }

        #expect(title(for: .alphabetical) == "alphabetical")
        #expect(title(for: .byPopulation) == "byPopulation")
        #expect(CountriesList.SortOrder.alphabetical != .byPopulation)
    }

    @Test func sortOrderDefaultsToAlphabetical() async throws {
        //harness:criterion=c-sort-order-default-alphabetical,c-sort-order-internal-visibility,c-alphabetical-sort-uses-name-keypath,c-sort-state-not-persisted
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let actualView = try view.actualView()
                let firstCell = try view.content().find(CountryCell.self).actualView()
                #expect(actualView.sortOrder == .alphabetical)
                #expect(firstCell.country.name == "Canada")
                container.interactors.verify()
            }
        }
    }

    @Test func sortToolbarButtonsAreVisibleTogether() async throws {
        //harness:criterion=c-toolbar-button-exists-alongside-permissions
        let container = DIContainer(interactors: .mocked())
        container.appState[\.permissions.push] = .notRequested
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                #expect(throws: Never.self) { try view.find(button: "Sort by Population") }
                #expect(throws: Never.self) { try view.find(button: "Allow Push") }
                container.interactors.verify()
            }
        }
    }

    @Test func sortToolbarButtonTogglesSortOrderWithoutReload() async throws {
        //harness:criterion=c-toolbar-button-toggles-sort-order,c-sort-toggle-does-not-trigger-network-reload
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let sortOrder = try view.actualView().sortOrder
                #expect(sortOrder == .alphabetical)
                try view.find(button: "Sort by Population").tap()
            }
            try await sut.inspection.inspect { view in
                let sortOrder = try view.actualView().sortOrder
                #expect(sortOrder == .byPopulation)
                try view.find(button: "Sort Alphabetically").tap()
            }
            try await sut.inspection.inspect { view in
                let sortOrder = try view.actualView().sortOrder
                #expect(sortOrder == .alphabetical)
                container.interactors.verify()
            }
        }
    }

    @Test func sortByPopulationShowsHighestFirst() async throws {
        //harness:criterion=c-query-accepts-sort-discriminator,c-query-container-equality-includes-sort,c-population-sort-uses-population-keypath-descending,c-population-sort-highest-population-first
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.actualView().sortOrder = .byPopulation
            }
            try await sut.inspection.inspect { view in
                let firstCell = try view.content().find(CountryCell.self).actualView()
                #expect(firstCell.country.name == "United States")
                container.interactors.verify()
            }
        }
    }

    @Test func searchFiltersResultsWhenSortedByPopulation() async throws {
        //harness:criterion=c-search-filters-when-population-sort-active
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)
        let searchText = "a"
        let expectedNames = dbCountries
            .filter { $0.name.localizedStandardContains(searchText) }
            .sorted { $0.population > $1.population }
            .map(\.name)

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.actualView().sortOrder = .byPopulation
                try view.actualView().searchText = searchText
            }
            try await sut.inspection.inspect { view in
                let cells = try view.content().findAll(CountryCell.self)
                let names = try cells.map { try $0.actualView().country.name }
                #expect(names == expectedNames)
                #expect(names.allSatisfy { $0.localizedStandardContains(searchText) })
                container.interactors.verify()
            }
        }
    }

    @Test func refreshWorksWithPopulationSortActive() async throws {
        //harness:criterion=c-refreshable-preserved
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
                try view.actualView().sortOrder = .byPopulation
            }
            try await sut.inspection.inspect { view in
                let list = try view.find(ViewType.List.self)
                try await list.callRefreshable()
                container.interactors.verify()
            }
        }
    }

    @Test func deepLinkRoutingStillSelectsCountry() async throws {
        //harness:criterion=c-navigation-link-preserved,c-deep-link-routing-preserved
        var appState = AppState()
        appState.routing.countriesList.countryCode = apiCountries[0].alpha3Code
        let store = Store(appState)
        let container = DIContainer(appState: store, interactors: .mocked())
        let sut = CountriesList()
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let actualView = try view.actualView()
                #expect(!actualView.navigationPath.isEmpty)
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
}

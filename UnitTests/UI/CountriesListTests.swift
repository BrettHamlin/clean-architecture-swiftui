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

    //harness:criterion=c-sort-state-default-false,c-sort-state-ephemeral-resets
    @Test func sortByPopulationDefaultsToFalse() async throws {
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let view = sut.inject(container).modelContainer(ModelContainer.mock)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let sortByPopulation = try view.actualView().sortByPopulation
                #expect(sortByPopulation == false)
                container.interactors.verify()
            }
        }
    }

    //harness:criterion=c-sort-alphabetical-default-order,c-search-filter-preserved-alpha-mode,c-post-query-sort-no-queryviewcontainer-change
    @Test func visibleCountriesSortsAlphabeticallyByDefaultAndPreservesSearchFiltering() {
        let visibleCountries = CountriesList.makeVisibleCountries(
            from: dbCountries,
            searchText: "",
            sortByPopulation: false
        )
        let expectedCountries = dbCountries.sorted { $0.name < $1.name }
        #expect(visibleCountries.map(\.name) == expectedCountries.map(\.name))

        let filteredCountries = CountriesList.makeVisibleCountries(
            from: dbCountries,
            searchText: "Canada",
            sortByPopulation: false
        )
        #expect(filteredCountries.map(\.name) == ["Canada"])
    }

    //harness:criterion=c-sort-population-desc-order,c-sort-population-name-tiebreaker
    @Test func visibleCountriesSortsByPopulationDescendingWithNameTieBreaker() {
        let populationSortedCountries = CountriesList.makeVisibleCountries(
            from: dbCountries,
            searchText: "",
            sortByPopulation: true
        )
        #expect(populationSortedCountries.prefix(3).map(\.name) == ["United States", "Canada", "Georgia"])

        let tiedPopulationCountries = [
            DBModel.Country(name: "Zaria", translations: [:], population: 10, alpha3Code: "ZAR"),
            DBModel.Country(name: "Alpha", translations: [:], population: 10, alpha3Code: "ALP")
        ]
        let tieSortedCountries = CountriesList.makeVisibleCountries(
            from: tiedPopulationCountries,
            searchText: "",
            sortByPopulation: true
        )
        #expect(tieSortedCountries.map(\.name) == ["Alpha", "Zaria"])
    }

    //harness:criterion=c-sort-and-search-compose,c-visible-countries-used-in-list
    @Test func visibleCountriesAppliesSearchBeforePopulationSort() {
        let countries = [
            DBModel.Country(name: "Low Match", translations: [:], population: 10, alpha3Code: "LOW"),
            DBModel.Country(name: "Outside Search", translations: [:], population: 1000, alpha3Code: "OUT"),
            DBModel.Country(name: "High Match", translations: [:], population: 100, alpha3Code: "HIG")
        ]
        let visibleCountries = CountriesList.makeVisibleCountries(
            from: countries,
            searchText: "Match",
            sortByPopulation: true
        )
        #expect(visibleCountries.map(\.name) == ["High Match", "Low Match"])
    }

    //harness:criterion=c-empty-state-uses-visible-countries
    @Test func noMatchesWhenSearchingInPopulationSortMode() async throws {
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.actualView().searchText = "ZZZNOMATCH"
                try view.actualView().sortByPopulation = true
            }
            try await sut.inspection.inspect { view in
                #expect(throws: Never.self) { try view.find(text: "No matches found") }
                container.interactors.verify()
            }
        }
    }

    //harness:criterion=c-sort-toggle-no-interactor-call,c-sort-no-network-refresh
    @Test func togglingSortDoesNotCallInteractors() async throws {
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.actualView().sortByPopulation = false
                try view.actualView().sortByPopulation = true
                container.interactors.verify()
            }
        }
    }

    //harness:criterion=c-sort-toggle-toolbar-item-present,c-sort-toggle-sf-symbol-icon,c-permissions-button-preserved,c-sort-toggle-accessibility-label,c-localizable-strings-added
    @Test func toolbarContainsSortToggleAndPermissionsButton() async throws {
        let container = DIContainer(interactors: .mocked())
        container.appState[\.permissions.push] = .notRequested
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let toolbar = try view.content().find(ViewType.List.self).toolbar()
                let sortButton = try toolbar.item(0).button()
                let sortLabel = try sortButton.accessibilityLabel().string()
                let sortIconName = try sortButton.labelView().label().icon().image().labelView().string()
                let permissionsButtonTitle = try toolbar.item(1).button().labelView().text().string()

                #expect(sortLabel == NSLocalizedString("Sort by Population", comment: ""))
                #expect(sortIconName.isEmpty == false)
                #expect(permissionsButtonTitle == "Allow Push")

                try sortButton.tap()
            }
            try await sut.inspection.inspect { view in
                let toolbar = try view.content().find(ViewType.List.self).toolbar()
                let sortButton = try toolbar.item(0).button()
                let sortLabel = try sortButton.accessibilityLabel().string()

                #expect(sortLabel == NSLocalizedString("Sort Alphabetically", comment: ""))
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

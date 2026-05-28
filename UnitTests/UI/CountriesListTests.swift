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

    @Test func sortDefaultsToAlphabetical() async throws {
        //harness:criterion=c-sort-state-default-false,c-sort-descriptor-alphabetical-default
        let names = try await queryCountryNames(searchText: "", sortByPopulation: false)
        let expectedNames = apiCountries.sorted { $0.name < $1.name }.map(\.name)
        #expect(names == expectedNames)

        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = try await seededModelContainer()
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let actualView = try view.actualView()
                let sortButton = try view.sortButton()
                let sortValue = try sortButton.accessibilityValue().string()
                #expect(actualView.sortByPopulation == false)
                #expect(sortValue == "Alphabetical")
                container.interactors.verify()
            }
        }
    }

    @Test func toolbarContainsSortControlAndPermissionsButton() async throws {
        //harness:criterion=c-sort-toggle-exists-in-toolbar,c-permissions-button-still-present
        let container = DIContainer(interactors: .mocked())
        container.appState[\.permissions.push] = .notRequested
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = try await seededModelContainer()
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let toolbar = try view.content().find(ViewType.List.self).toolbar()
                _ = try toolbar.item(0).find(ViewType.Button.self) { button in
                    try button.accessibilityIdentifier() == "sortByPopulationButton"
                }
                _ = try toolbar.item(1).find(button: "Allow Push")
                container.interactors.verify()
            }
        }
    }

    @Test func populationSortUsesDescendingPopulationOrder() async throws {
        //harness:criterion=c-sort-descriptor-population-after-toggle,c-population-sort-deterministic-with-mocked-data
        let result = try await queryCountries(searchText: "", sortByPopulation: true)
        let expectedNames = apiCountries
            .sorted { $0.population > $1.population }
            .map(\.name)
        let resultNames = result.map(\.name)
        #expect(resultNames == expectedNames)

        let populationsAreDescending = zip(result, result.dropFirst()).allSatisfy { pair in
            pair.0.population >= pair.1.population
        }
        #expect(populationsAreDescending)
    }

    @Test func togglingSortDoesNotCallInteractorsOrMutateAppState() async throws {
        //harness:criterion=c-sort-toggle-no-interactor-calls,c-sort-state-ephemeral
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = try await seededModelContainer()
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let sortButton = try view.sortButton()
                try sortButton.tap()
            }
            try await sut.inspection.inspect { view in
                let actualView = try view.actualView()
                let sortButton = try view.sortButton()
                let sortValue = try sortButton.accessibilityValue().string()
                #expect(actualView.sortByPopulation == true)
                #expect(sortValue == "Population")
                #expect(container.appState.value == AppState())
                container.interactors.verify()
            }
        }
    }

    @Test func searchFiltersThroughQueryInBothSortModes() async throws {
        //harness:criterion=c-search-filters-under-alphabetical-sort,c-search-filters-under-population-sort
        let searchText = "ge"
        let expectedNames = apiCountries
            .filter { $0.name.localizedStandardContains(searchText) }
            .map(\.name)

        let alphabeticalNames = try await queryCountryNames(searchText: searchText, sortByPopulation: false)
        let populationSortedNames = try await queryCountryNames(searchText: searchText, sortByPopulation: true)

        #expect(Set(alphabeticalNames) == Set(expectedNames))
        #expect(Set(populationSortedNames) == Set(expectedNames))
        #expect(alphabeticalNames.count == expectedNames.count)
        #expect(populationSortedNames.count == expectedNames.count)
    }

    @Test func sortToggleResetsOnFreshCountriesListInstance() async throws {
        //harness:criterion=c-sort-toggle-resets-on-reinit
        let firstContainer = DIContainer(interactors: .mocked())
        let firstSut = CountriesList(state: .loaded(()))
        let firstModelContainer = try await seededModelContainer()
        let firstView = firstSut
            .inject(firstContainer)
            .modelContainer(firstModelContainer)
        try await ViewHosting.host(firstView) {
            try await firstSut.inspection.inspect { view in
                let sortButton = try view.sortButton()
                try sortButton.tap()
            }
            try await firstSut.inspection.inspect { view in
                let actualView = try view.actualView()
                #expect(actualView.sortByPopulation == true)
                firstContainer.interactors.verify()
            }
        }

        let secondContainer = DIContainer(interactors: .mocked())
        let secondSut = CountriesList(state: .loaded(()))
        let secondModelContainer = try await seededModelContainer()
        let secondView = secondSut
            .inject(secondContainer)
            .modelContainer(secondModelContainer)
        try await ViewHosting.host(secondView) {
            try await secondSut.inspection.inspect { view in
                let actualView = try view.actualView()
                let sortButton = try view.sortButton()
                let sortValue = try sortButton.accessibilityValue().string()
                #expect(actualView.sortByPopulation == false)
                #expect(sortValue == "Alphabetical")
                secondContainer.interactors.verify()
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

    private func seededModelContainer() async throws -> ModelContainer {
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        return modelContainer
    }

    private func queryCountryNames(
        searchText: String,
        sortByPopulation: Bool
    ) async throws -> [String] {
        let countries = try await queryCountries(
            searchText: searchText,
            sortByPopulation: sortByPopulation
        )
        return countries.map(\.name)
    }

    private func queryCountries(
        searchText: String,
        sortByPopulation: Bool
    ) async throws -> [DBModel.Country] {
        let modelContainer = try await seededModelContainer()
        let expectation = TestExpectation()
        var result: [DBModel.Country] = []
        let probe = CountriesQueryProbe(
            searchText: searchText,
            sortByPopulation: sortByPopulation
        ) { countries in
            result = countries
            expectation.fulfill()
        }
        .modelContainer(modelContainer)
        try await ViewHosting.host(probe) {
            await expectation.fulfillment()
        }
        return result
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

    func sortButton() throws -> InspectableView<ViewType.Button> {
        try content().find(ViewType.Button.self) { button in
            try button.accessibilityIdentifier() == "sortByPopulationButton"
        }
    }
}

// MARK: - Query inspection helper

private struct CountriesQueryProbe: View {

    @Query private var countries: [DBModel.Country]
    let onResults: ([DBModel.Country]) -> Void

    init(
        searchText: String,
        sortByPopulation: Bool,
        onResults: @escaping ([DBModel.Country]) -> Void
    ) {
        _countries = CountriesList.countriesQuery(
            searchText: searchText,
            sortByPopulation: sortByPopulation
        )
        self.onResults = onResults
    }

    var body: some View {
        Rectangle()
            .hidden()
            .onChange(of: countries, initial: true) { _, countries in
                onResults(countries)
            }
    }
}

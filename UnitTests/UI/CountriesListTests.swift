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
        //harness:criterion=c-no-matches-alphabetical-sort
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

    @Test func noMatchesWhenSearchingWithPopulationSort() async throws {
        //harness:criterion=c-no-matches-population-sort,c-test-search-plus-sort-no-matches
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.actualView().searchText = "nomatch"
                try view.actualView().sortByPopulation = false
            }
            try await sut.inspection.inspect { view in
                #expect(throws: Never.self) { try view.find(text: "No matches found") }
                try view.actualView().sortByPopulation = true
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
        //harness:criterion=c-sort-state-property-exists,c-sort-state-default-false
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
                let actualView = try view.actualView()
                #expect(actualView.sortByPopulation == false)
                #expect(container.appState.value == AppState())
                container.interactors.verify()
            }
        }
    }

    @Test func defaultAlphabeticalOrderPreservesQueryOrdering() throws {
        //harness:criterion=c-alphabetical-sort-descriptor-correct,c-test-default-alphabetical-order
        let queryOrderedCountries = dbCountries.sorted { $0.name < $1.name }
        let sortedCountries = CountriesList.sortedCountries(queryOrderedCountries, sortByPopulation: false)
        let expectedNames = dbCountries.sorted { $0.name < $1.name }.map(\.name)

        #expect(sortedCountries.map(\.name) == expectedNames)
        #expect(sortedCountries.first?.name == expectedNames.first)
    }

    @Test func populationDescendingOrder() throws {
        //harness:criterion=c-population-sort-descriptor-correct,c-list-uses-sorted-array,c-test-population-descending-order
        let sortedCountries = CountriesList.sortedCountries(dbCountries, sortByPopulation: true)
        let expectedPopulations = dbCountries.sorted { $0.population > $1.population }.map(\.population)

        #expect(sortedCountries.map(\.population) == expectedPopulations)
        #expect(sortedCountries.first?.population == expectedPopulations.first)
    }

    @Test func searchFilterComposesWithPopulationSort() throws {
        //harness:criterion=c-sort-does-not-alter-search-filter
        let searchText = "United"
        let filteredCountries = dbCountries.filter { country in
            country.name.localizedStandardContains(searchText)
        }
        let sortedCountries = CountriesList.sortedCountries(filteredCountries, sortByPopulation: true)
        let expectedCountries = dbCountries
            .filter { $0.name.localizedStandardContains(searchText) }
            .sorted { $0.population > $1.population }

        #expect(sortedCountries.map(\.alpha3Code) == expectedCountries.map(\.alpha3Code))
    }

    @Test func sortToggleChangesStateWithoutRefreshing() async throws {
        //harness:criterion=c-sort-toggle-toolbar-item-present,c-sort-toggle-changes-sort-by-population,c-sort-does-not-trigger-network-refresh
        let container = DIContainer(interactors: .mocked())
        container.appState[\.permissions.push] = .notRequested
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let actualView = try view.actualView()
                #expect(actualView.sortByPopulation == false)
                #expect(throws: Never.self) {
                    try view.find(viewWithAccessibilityIdentifier: "permissionsButton")
                }
                let sortButton = try view.find(viewWithAccessibilityIdentifier: "sortByPopulationButton")
                try sortButton.button().tap()
            }
            try await sut.inspection.inspect { view in
                let actualView = try view.actualView()
                #expect(actualView.sortByPopulation == true)
                let sortButton = try view.find(viewWithAccessibilityIdentifier: "sortByPopulationButton")
                try sortButton.button().tap()
            }
            try await sut.inspection.inspect { view in
                let actualView = try view.actualView()
                #expect(actualView.sortByPopulation == false)
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
        //harness:criterion=c-permissions-button-still-present
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

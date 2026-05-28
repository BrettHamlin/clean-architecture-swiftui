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

    @Test func sortByPopulationDefaultsToFalse() async throws {
        //harness:criterion=c-sort-state-default-false,c-sort-state-not-persisted
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let view = sut.inject(container)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let sortByPopulation = try view.actualView().sortByPopulation
                #expect(sortByPopulation == false)
            }
        }
    }

    @Test func sortByPopulationCanBeSetToTrue() async throws {
        //harness:criterion=c-sort-state-toggle-flips
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let view = sut.inject(container)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.actualView().sortByPopulation = true
                let sortByPopulation = try view.actualView().sortByPopulation
                #expect(sortByPopulation == true)
            }
        }
    }

    @Test func toolbarContainsSortAndPermissionsButtons() async throws {
        //harness:criterion=c-toolbar-sort-button-present,c-permissions-button-still-present
        let container = DIContainer(interactors: .mocked())
        container.appState[\.permissions.push] = .notRequested
        let sut = CountriesList(state: .loaded(()))
        let view = sut.inject(container)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                _ = try view.find(viewWithAccessibilityIdentifier: "sortByPopulationButton")
                _ = try view.find(button: "Allow Push")
                container.interactors.verify()
            }
        }
    }

    @Test func tappingSortButtonTogglesStateWithoutRefreshing() async throws {
        //harness:criterion=c-toolbar-sort-button-flips-state,c-refresh-not-triggered-on-sort-toggle
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let view = sut.inject(container)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let initialSortByPopulation = try view.actualView().sortByPopulation
                #expect(initialSortByPopulation == false)
                try view.find(viewWithAccessibilityIdentifier: "sortByPopulationButton").button().tap()
                let toggledSortByPopulation = try view.actualView().sortByPopulation
                #expect(toggledSortByPopulation == true)
                container.interactors.verify()
            }
            try await sut.inspection.inspect { view in
                try view.find(viewWithAccessibilityIdentifier: "sortByPopulationButton").button().tap()
                let toggledBackSortByPopulation = try view.actualView().sortByPopulation
                #expect(toggledBackSortByPopulation == false)
                container.interactors.verify()
            }
        }
    }

    @Test func defaultSortDescriptorsOrderCountriesAlphabetically() {
        //harness:criterion=c-query-default-alpha-sort,c-default-alpha-order-test
        let descriptors = CountriesList.sortDescriptors(sortByPopulation: false)
        let sortedCountries = dbCountries.sorted(using: descriptors)

        #expect(descriptors.count == 1)
        #expect(descriptors.first?.order == .forward)
        #expect(sortedCountries.map(\.name) == ["Canada", "Georgia", "United States"])
    }

    @Test func populationSortDescriptorsOrderCountriesByPopulationDescending() {
        //harness:criterion=c-query-population-sort-descriptors,c-population-desc-order-test
        let descriptors = CountriesList.sortDescriptors(sortByPopulation: true)
        let sortedCountries = dbCountries.sorted(using: descriptors)

        #expect(descriptors.count == 2)
        #expect(descriptors.first?.order == .reverse)
        #expect(descriptors.last?.order == .forward)
        #expect(sortedCountries.map(\.name) == ["United States", "Canada", "Georgia"])
    }

    @Test func searchAndPopulationSortCompose() {
        //harness:criterion=c-search-plus-sort-test
        let searchText = "a"
        let descriptors = CountriesList.sortDescriptors(sortByPopulation: true)
        let filteredAndSorted = dbCountries
            .filter { $0.name.localizedStandardContains(searchText) }
            .sorted(using: descriptors)
        let expected = dbCountries
            .filter { $0.name.localizedStandardContains(searchText) }
            .sorted {
                if $0.population == $1.population {
                    return $0.name < $1.name
                }
                return $0.population > $1.population
            }

        #expect(filteredAndSorted.map(\.name) == expected.map(\.name))
        #expect(filteredAndSorted.map(\.name) == ["United States", "Canada", "Georgia"])
    }

    @Test func queryViewContainerEqualityIncludesSortKey() {
        //harness:criterion=c-query-view-container-equality-includes-sort,c-query-view-container-recreated-on-toggle
        let alphabetical = queryViewContainer(searchText: "Can", sortByPopulation: false)
        let population = queryViewContainer(searchText: "Can", sortByPopulation: true)
        let matchingAlphabetical = queryViewContainer(searchText: "Can", sortByPopulation: false)

        #expect(alphabetical != population)
        #expect(alphabetical == matchingAlphabetical)
    }

    @Test func togglingSortDoesNotChangeSearchText() async throws {
        //harness:criterion=c-search-unaffected-by-sort-toggle
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let view = sut.inject(container)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.actualView().searchText = "Can"
                try view.find(viewWithAccessibilityIdentifier: "sortByPopulationButton").button().tap()
                let searchText = try view.actualView().searchText
                #expect(searchText == "Can")
                container.interactors.verify()
            }
        }
    }

    @Test func navigationLinksRenderWhenSortedByPopulation() async throws {
        //harness:criterion=c-navigation-link-preserved
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.actualView().sortByPopulation = true
            }
            try await sut.inspection.inspect { view in
                let content = try view.content()
                _ = try content.find(ViewType.NavigationLink.self)
                container.interactors.verify()
            }
        }
    }

    @Test func pullToRefreshWorksWhenSortedByPopulation() async throws {
        //harness:criterion=c-pull-to-refresh-preserved
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
                try view.actualView().sortByPopulation = true
                let list = try view.find(ViewType.List.self)
                try await list.callRefreshable()
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

@MainActor private func queryViewContainer(
    searchText: String,
    sortByPopulation: Bool
) -> QueryViewContainer<DBModel.Country, Bool> {
    QueryViewContainer(
        searchText: searchText,
        sortKey: sortByPopulation,
        builder: { _ in
            Query(sort: CountriesList.sortDescriptors(sortByPopulation: sortByPopulation))
        },
        results: { _, _ in }
    )
}

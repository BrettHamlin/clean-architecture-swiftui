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
        //harness:criterion=c-searchable-modifier-preserved
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
        //harness:criterion=c-refreshable-modifier-preserved
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
        //harness:criterion=c-onchange-routing-preserved,c-existing-alpha-test-stays-green
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

    @Test func defaultSortOrderIsAlphabetical() async throws {
        //harness:criterion=c-sort-state-declared,c-sort-default-alphabetical,c-sort-state-ephemeral
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let sortOrder = try view.actualView().sortOrder
                #expect(sortOrder == .alphabetical)
                container.interactors.verify()
            }
        }
    }

    @Test func sortAndPermissionsToolbarButtonsArePresent() async throws {
        //harness:criterion=c-sort-toggle-toolbar-item-present
        let container = DIContainer(interactors: .mocked())
        container.appState[\.permissions.push] = .notRequested
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let sortButton = try view.find(button: "Sort by Population")
                let permissionsButton = try view.find(button: "Allow Push")
                _ = sortButton
                _ = permissionsButton
                container.interactors.verify()
            }
        }
    }

    @Test func sortToolbarButtonTogglesSortOrder() async throws {
        //harness:criterion=c-sort-toggle-switches-to-population,c-sort-toggle-switches-back-to-alpha
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let initialSortOrder = try view.actualView().sortOrder
                #expect(initialSortOrder == .alphabetical)

                let sortButton = try view.find(button: "Sort by Population")
                try sortButton.tap()
                let populationSortOrder = try view.actualView().sortOrder
                #expect(populationSortOrder == .populationDescending)

                try sortButton.tap()
                let alphabeticalSortOrder = try view.actualView().sortOrder
                #expect(alphabeticalSortOrder == .alphabetical)
                container.interactors.verify()
            }
        }
    }

    @Test func queryViewContainerEqualityIncludesSortOrder() {
        //harness:criterion=c-query-container-equality-includes-sort
        let alphabeticalContainer = QueryViewContainer<DBModel.Country, CountriesList.SortOrder>(
            searchText: "a",
            sortOrder: .alphabetical,
            builder: { searchText, sortOrder in
                Query(filter: CountriesList.searchPredicate(searchText), sort: sortOrder.sortDescriptors)
            },
            results: { _, _ in }
        )
        let populationContainer = QueryViewContainer<DBModel.Country, CountriesList.SortOrder>(
            searchText: "a",
            sortOrder: .populationDescending,
            builder: { searchText, sortOrder in
                Query(filter: CountriesList.searchPredicate(searchText), sort: sortOrder.sortDescriptors)
            },
            results: { _, _ in }
        )

        #expect(alphabeticalContainer != populationContainer)
    }

    @Test func alphabeticalDescriptorFetchesCountriesByName() async throws {
        //harness:criterion=c-alpha-sort-descriptor-applied,c-alpha-sort-plus-search-preserves-filter,c-searchable-modifier-preserved
        let modelContainer = try await seededModelContainer()

        let countries = try modelContainer.mainContext.fetch(
            CountriesList.fetchDescriptor(searchText: "a", sortOrder: .alphabetical)
        )

        #expect(countries.map(\.name) == ["Canada", "Georgia"])
    }

    @Test func populationDescriptorFetchesCountriesByDescendingPopulation() async throws {
        //harness:criterion=c-population-sort-descriptor-applied,c-population-sort-first-row-united-states
        let modelContainer = try await seededModelContainer()

        let countries = try modelContainer.mainContext.fetch(
            CountriesList.fetchDescriptor(searchText: "", sortOrder: .populationDescending)
        )
        let firstCountry = try #require(countries.first)

        #expect(firstCountry.name == "United States")
    }

    @Test func populationDescriptorCombinesWithSearchFilter() async throws {
        //harness:criterion=c-population-sort-descriptor-applied,c-population-sort-plus-search-filters
        let modelContainer = try await seededModelContainer()

        let countries = try modelContainer.mainContext.fetch(
            CountriesList.fetchDescriptor(searchText: "a", sortOrder: .populationDescending)
        )

        #expect(countries.map(\.name) == ["Canada", "Georgia"])
    }

    @Test func togglingSortDoesNotCallInteractors() async throws {
        //harness:criterion=c-sort-toggle-no-refresh-interactor,c-sort-toggle-no-detail-interactor,c-sort-toggle-no-permission-interactor
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.find(button: "Sort by Population").tap()
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
        //harness:criterion=c-permissions-button-preserved
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

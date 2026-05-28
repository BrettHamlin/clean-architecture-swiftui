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

    @Test func populationSortStateDefaultsToFalseAndIsNotPersisted() async throws {
        //harness:criterion=c-sort-state-default-false,c-sort-state-not-persisted,c-mock-container-seeded-tests
        let firstModelContainer = try await seededModelContainer()
        let first = CountriesList(state: .loaded(()))
        let firstView = first
            .inject(DIContainer(interactors: .mocked()))
            .modelContainer(firstModelContainer)
        try await ViewHosting.host(firstView) {
            try await first.inspection.inspect { view in
                let actualView = try view.actualView()
                #expect(actualView.sortByPopulation == false)
                try view.actualView().sortByPopulation = true
            }
            try await first.inspection.inspect { view in
                let actualView = try view.actualView()
                #expect(actualView.sortByPopulation == true)
            }
        }

        let secondModelContainer = try await seededModelContainer()
        let second = CountriesList(state: .loaded(()))
        let secondView = second
            .inject(DIContainer(interactors: .mocked()))
            .modelContainer(secondModelContainer)
        try await ViewHosting.host(secondView) {
            try await second.inspection.inspect { view in
                let actualView = try view.actualView()
                #expect(actualView.sortByPopulation == false)
            }
        }
    }

    @Test func populationSortToolbarButtonExistsAndTogglesState() async throws {
        //harness:criterion=c-sort-toolbar-item-exists,c-sort-toolbar-toggle-flips-state,c-default-sort-descriptor-is-alphabetical,c-population-sort-descriptor-is-descending,c-mock-container-seeded-tests
        let container = DIContainer(interactors: .mocked())
        container.appState[\.permissions.push] = .notRequested
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = try await seededModelContainer()
        let view = sut.inject(container).modelContainer(modelContainer)
        let alphabeticalSort = SortDescriptor(\DBModel.Country.name, order: .forward)
        let populationSort = SortDescriptor(\DBModel.Country.population, order: .reverse)

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let queryContainer = try view.find(QueryViewContainer<DBModel.Country>.self).actualView()
                #expect(queryContainer.sort == .some(alphabeticalSort))
                #expect(throws: Never.self) { try view.find(button: "Allow Push") }
                let sortButton = try view.find(button: "Sort by Population")
                try sortButton.tap()
            }
            try await sut.inspection.inspect { view in
                let actualView = try view.actualView()
                let queryContainer = try view.find(QueryViewContainer<DBModel.Country>.self).actualView()
                #expect(actualView.sortByPopulation == true)
                #expect(queryContainer.sort == .some(populationSort))
                let sortButton = try view.find(button: "Sort Alphabetically")
                try sortButton.tap()
            }
            try await sut.inspection.inspect { view in
                let actualView = try view.actualView()
                let queryContainer = try view.find(QueryViewContainer<DBModel.Country>.self).actualView()
                #expect(actualView.sortByPopulation == false)
                #expect(queryContainer.sort == .some(alphabeticalSort))
                #expect(throws: Never.self) { try view.find(button: "Sort by Population") }
            }
        }
    }

    @Test func permissionsButtonIsPreservedAcrossSortModes() async throws {
        //harness:criterion=c-permissions-button-preserved,c-mock-container-seeded-tests
        let container = DIContainer(interactors: .mocked(permissions: [
            .request(.pushNotifications),
            .request(.pushNotifications)
        ]))
        container.appState[\.permissions.push] = .notRequested
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = try await seededModelContainer()
        let view = sut.inject(container).modelContainer(modelContainer)

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let permissionsButton = try view.find(button: "Allow Push")
                try permissionsButton.tap()
                let sortButton = try view.find(button: "Sort by Population")
                try sortButton.tap()
            }
            try await sut.inspection.inspect { view in
                let actualView = try view.actualView()
                #expect(actualView.sortByPopulation == true)
                let permissionsButton = try view.find(button: "Allow Push")
                try permissionsButton.tap()
                container.interactors.verify()
            }
        }
    }

    @Test func queryHelperAcceptsSortDescriptorParameter() async throws {
        //harness:criterion=c-query-helper-accepts-sort-param,c-mock-container-seeded-tests
        _ = try await seededModelContainer()
        let results = BindingWithHistory(value: [DBModel.Country]())
        let view = EmptyView().query(
            searchText: "",
            sort: SortDescriptor(\DBModel.Country.name, order: .forward),
            results: results.binding
        ) { search, sort in
            Query(filter: #Predicate<DBModel.Country> { country in
                if search.isEmpty {
                    return true
                } else {
                    return country.name.localizedStandardContains(search)
                }
            }, sort: [sort])
        }
        _ = view
        #expect(results.history.count == 1)
        #expect(results.history[0].isEmpty)
    }

    @Test func queryViewContainerEqualityIncludesSortState() async throws {
        //harness:criterion=c-query-view-container-equality-includes-sort,c-query-container-same-sort-equal,c-mock-container-seeded-tests
        _ = try await seededModelContainer()
        let alphabeticalSort = SortDescriptor(\DBModel.Country.name, order: .forward)
        let populationSort = SortDescriptor(\DBModel.Country.population, order: .reverse)
        let alphabetical = queryContainer(searchText: "a", sort: alphabeticalSort)
        let sameAlphabetical = queryContainer(searchText: "a", sort: alphabeticalSort)
        let population = queryContainer(searchText: "a", sort: populationSort)

        #expect(alphabetical == sameAlphabetical)
        #expect(alphabetical != population)
    }

    @Test func queryViewBuilderReceivesAlphabeticalSortDescriptor() async throws {
        //harness:criterion=c-query-view-uses-sort-descriptor-alphabetical,c-default-sort-descriptor-is-alphabetical,c-mock-container-seeded-tests
        _ = try await seededModelContainer()
        let expected = SortDescriptor(\DBModel.Country.name, order: .forward)
        var receivedSort: SortDescriptor<DBModel.Country>?
        let container = queryContainer(searchText: "", sort: expected) { _, sort in
            receivedSort = sort
        }

        _ = container.body

        #expect(container.searchText == "")
        #expect(container.sort == .some(expected))
        #expect(receivedSort == .some(expected))
    }

    @Test func queryViewBuilderReceivesPopulationSortDescriptor() async throws {
        //harness:criterion=c-query-view-uses-sort-descriptor-population,c-population-sort-descriptor-is-descending,c-mock-container-seeded-tests
        _ = try await seededModelContainer()
        let expected = SortDescriptor(\DBModel.Country.population, order: .reverse)
        var receivedSort: SortDescriptor<DBModel.Country>?
        let container = queryContainer(searchText: "", sort: expected) { _, sort in
            receivedSort = sort
        }

        _ = container.body

        #expect(container.searchText == "")
        #expect(container.sort == .some(expected))
        #expect(receivedSort == .some(expected))
    }

    @Test func searchAndPopulationSortComposeWithoutRefresh() async throws {
        //harness:criterion=c-search-and-population-sort-compose,c-mock-container-seeded-tests
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = try await seededModelContainer()
        let view = sut.inject(container).modelContainer(modelContainer)
        let expected = SortDescriptor(\DBModel.Country.population, order: .reverse)

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.actualView().sortByPopulation = true
                try view.actualView().searchText = "a"
            }
            try await sut.inspection.inspect { view in
                let actualView = try view.actualView()
                let queryContainer = try view.find(QueryViewContainer<DBModel.Country>.self).actualView()
                #expect(queryContainer.searchText == "a")
                #expect(queryContainer.sort == .some(expected))
                #expect(actualView.sortByPopulation == true)
                container.interactors.verify()
            }
        }
    }

    @Test func searchOnlyKeepsAlphabeticalSort() async throws {
        //harness:criterion=c-search-only-does-not-affect-sort-state,c-mock-container-seeded-tests
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = try await seededModelContainer()
        let view = sut.inject(container).modelContainer(modelContainer)
        let expected = SortDescriptor(\DBModel.Country.name, order: .forward)

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.actualView().searchText = "a"
            }
            try await sut.inspection.inspect { view in
                let actualView = try view.actualView()
                let queryContainer = try view.find(QueryViewContainer<DBModel.Country>.self).actualView()
                #expect(actualView.sortByPopulation == false)
                #expect(queryContainer.searchText == "a")
                #expect(queryContainer.sort == .some(expected))
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

    private func seededModelContainer() async throws -> ModelContainer {
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        return modelContainer
    }

    private func queryContainer(
        searchText: String,
        sort: SortDescriptor<DBModel.Country>,
        onBuild: @escaping (String, SortDescriptor<DBModel.Country>?) -> Void = { _, _ in }
    ) -> QueryViewContainer<DBModel.Country> {
        QueryViewContainer(
            searchText: searchText,
            sort: sort,
            builder: { search, sort in
                onBuild(search, sort)
                return Query(filter: #Predicate<DBModel.Country> { country in
                    if search.isEmpty {
                        return true
                    } else {
                        return country.name.localizedStandardContains(search)
                    }
                }, sort: sort.map { [$0] } ?? [])
            },
            results: { _, _ in }
        )
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

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

    //harness:criterion=c-search-behavior-unchanged
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

    //harness:criterion=c-sort-order-enum-cases,c-sort-order-state-default-alphabetical
    @Test func sortOrderDefaultsToAlphabetical() async throws {
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        try await ViewHosting.host(sut.inject(container)) {
            try await sut.inspection.inspect { view in
                let sortOrder = try view.actualView().sortOrder
                #expect(sortOrder == .alphabetical)
                #expect(sortOrder != .byPopulation)
                container.interactors.verify()
            }
        }
    }

    //harness:criterion=c-toolbar-toggle-present,c-sort-toggle-label-alphabetical,c-sort-toggle-label-population,c-permissions-button-still-present
    @Test func sortToggleAndPermissionsButtonShareToolbar() async throws {
        let container = DIContainer(interactors: .mocked())
        container.appState[\.permissions.push] = .notRequested
        let sut = CountriesList(state: .loaded(()))
        try await ViewHosting.host(sut.inject(container)) {
            try await sut.inspection.inspect { view in
                #expect(throws: Never.self) { try view.find(button: "Sort by Population") }
                #expect(throws: Never.self) { try view.find(button: "Allow Push") }
                try view.find(button: "Sort by Population").tap()
            }
            try await sut.inspection.inspect { view in
                let actualView = try view.actualView()
                #expect(actualView.sortOrder == .byPopulation)
                #expect(throws: Never.self) { try view.find(button: "Sort by Name") }
                #expect(throws: Never.self) { try view.find(button: "Allow Push") }
                container.interactors.verify()
            }
        }
    }

    //harness:criterion=c-toolbar-toggle-switches-sort,c-toggle-with-active-search-preserves-filter,c-no-interactor-side-effects-on-sort-toggle
    @Test func sortToggleSwitchesOrderWithoutChangingActiveSearch() async throws {
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        try await ViewHosting.host(sut.inject(container)) {
            try await sut.inspection.inspect { view in
                try view.actualView().searchText = "Can"
                let actualView = try view.actualView()
                #expect(actualView.sortOrder == .alphabetical)
                try view.find(button: "Sort by Population").tap()
            }
            try await sut.inspection.inspect { view in
                let actualView = try view.actualView()
                #expect(actualView.searchText == "Can")
                #expect(actualView.sortOrder == .byPopulation)
                try view.find(button: "Sort by Name").tap()
            }
            try await sut.inspection.inspect { view in
                let actualView = try view.actualView()
                #expect(actualView.searchText == "Can")
                #expect(actualView.sortOrder == .alphabetical)
                container.interactors.verify()
            }
        }
    }

    //harness:criterion=c-query-uses-name-asc-when-alphabetical,c-alphabetical-sort-descriptor-selects-name-asc
    @Test func alphabeticalSortDescriptorSelectsNameAscending() throws {
        let descriptor = CountriesList.SortOrder.alphabetical.sortDescriptor
        let canada = try country(named: "Canada")
        let unitedStates = try country(named: "United States")
        let comparison = descriptor.compare(canada, unitedStates)
        if #available(macOS 14, iOS 17, *) {
            let keyPath: PartialKeyPath<DBModel.Country> = \DBModel.Country.name
            #expect(descriptor.keyPath == keyPath)
        }
        #expect(descriptor.order == .forward)
        #expect(comparison == .orderedAscending)
    }

    //harness:criterion=c-query-uses-population-desc-when-by-population,c-population-sort-descriptor-selects-population-desc
    @Test func populationSortDescriptorSelectsPopulationDescending() throws {
        let descriptor = CountriesList.SortOrder.byPopulation.sortDescriptor
        let canada = try country(named: "Canada")
        let unitedStates = try country(named: "United States")
        let comparison = descriptor.compare(unitedStates, canada)
        if #available(macOS 14, iOS 17, *) {
            let keyPath: PartialKeyPath<DBModel.Country> = \DBModel.Country.population
            #expect(descriptor.keyPath == keyPath)
        }
        #expect(descriptor.order == .reverse)
        #expect(comparison == .orderedAscending)
    }

    //harness:criterion=c-query-search-equality-includes-sort-key
    @Test func queryContainerEqualityIncludesSortKey() {
        let lhs = QueryViewContainer<DBModel.Country, CountriesList.SortOrder>(
            searchText: "Can",
            sortKey: .alphabetical,
            builder: { _, _ in fatalError("Builder should not be evaluated for equality") },
            results: { _, _ in }
        )
        let rhs = QueryViewContainer<DBModel.Country, CountriesList.SortOrder>(
            searchText: "Can",
            sortKey: .byPopulation,
            builder: { _, _ in fatalError("Builder should not be evaluated for equality") },
            results: { _, _ in }
        )
        #expect(lhs != rhs)
    }

    //harness:criterion=c-view-query-accepts-sort-key
    @Test func viewQueryForwardsSearchTextAndSortKeyToBuilder() {
        let countries = BindingWithHistory(value: [DBModel.Country]())
        let queriedView = EmptyView().query(
            searchText: "Can",
            sortKey: CountriesList.SortOrder.byPopulation,
            results: countries.binding
        ) { _, sortOrder in
            return Query(
                filter: #Predicate<DBModel.Country> { _ in true },
                sort: [sortOrder.sortDescriptor]
            )
        }
        _ = queriedView
        var capturedSearchText: String?
        var capturedSortOrder: CountriesList.SortOrder?
        let container = QueryViewContainer<DBModel.Country, CountriesList.SortOrder>(
            searchText: "Can",
            sortKey: .byPopulation,
            builder: { searchText, sortOrder in
                capturedSearchText = searchText
                capturedSortOrder = sortOrder
                return Query(
                    filter: #Predicate<DBModel.Country> { _ in true },
                    sort: [sortOrder.sortDescriptor]
                )
            },
            results: { _, _ in }
        )
        _ = container.body
        #expect(capturedSearchText == "Can")
        #expect(capturedSortOrder == .byPopulation)
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

    //harness:criterion=c-pull-to-refresh-unaffected
    @Test func listRefreshUsesSameInteractorCallForEverySortOrder() async throws {
        for sortOrder in [CountriesList.SortOrder.alphabetical, .byPopulation] {
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
                    try view.actualView().sortOrder = sortOrder
                    let list = try view.find(ViewType.List.self)
                    try await list.callRefreshable()
                    container.interactors.verify()
                }
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

    //harness:criterion=c-no-persistence-or-repo-changes
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

    //harness:criterion=c-country-detail-navigation-unaffected
    @Test func countryRoutingNavigationWorksForEverySortOrder() async throws {
        for sortOrder in [CountriesList.SortOrder.alphabetical, .byPopulation] {
            let store = Store(AppState())
            let container = DIContainer(appState: store, interactors: .mocked())
            let sut = CountriesList(state: .loaded(()))
            let modelContainer = ModelContainer.mock
            let dbRepository = MainDBRepository(modelContainer: modelContainer)
            try await dbRepository.store(countries: apiCountries)
            let view = sut.inject(container).modelContainer(modelContainer)
            let country = try country(named: "Canada")
            try await ViewHosting.host(view) {
                try await sut.inspection.inspect { view in
                    try view.actualView().sortOrder = sortOrder
                    store[\.routing.countriesList.countryCode] = country.alpha3Code
                }
                try await sut.inspection.inspect { view in
                    let actualView = try view.actualView()
                    #expect(actualView.navigationPath.count == 1)
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

// MARK: - CountriesList test helpers

private extension CountriesListTests {
    func country(named name: String) throws -> DBModel.Country {
        return try #require(dbCountries.first(where: { $0.name == name }))
    }
}

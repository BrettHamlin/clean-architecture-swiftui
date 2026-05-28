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
        //harness:criterion=c-pull-to-refresh-unaffected
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
        //harness:criterion=c-alphabetical-sort-descriptor,c-alphabetical-sort-first-row-preserved
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

    @Test func sortOrderDefaultsAlphabetical() {
        //harness:criterion=c-sort-order-enum-defined,c-sort-state-defaults-alphabetical
        let sut = CountriesList(state: .loaded(()))
        let sortOrder: CountriesList.SortOrder = sut.sortOrder
        #expect(sortOrder == .alphabetical)
    }

    @Test func sortToggleInToolbarChangesSortOrder() async throws {
        //harness:criterion=c-sort-toggle-in-toolbar
        let container = DIContainer(interactors: .mocked())
        container.appState[\.permissions.push] = .notRequested
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let sortOrder = try view.actualView().sortOrder
                #expect(sortOrder == .alphabetical)
                #expect(throws: Never.self) { try view.find(button: "Allow Push") }
                try view.find(button: "Sort by Population").tap()
            }
            try await sut.inspection.inspect { view in
                let sortOrder = try view.actualView().sortOrder
                #expect(sortOrder == .populationDescending)
                container.interactors.verify()
            }
        }
    }

    @Test func sortToggleDoesNotTriggerRefresh() async throws {
        //harness:criterion=c-sort-toggle-no-interactor-call
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.find(button: "Sort by Population").tap()
            }
            try await sut.inspection.inspect(after: .seconds(0.1)) { _ in
                container.interactors.verify()
            }
        }
    }

    @Test func countriesLoadedSortedByPopulation() async throws {
        //harness:criterion=c-population-sort-descriptor,c-query-reissued-on-sort-toggle,c-population-sort-first-row-us
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)
        let unitedStates = try #require(dbCountries.first(where: { $0.alpha3Code == "USA" }))
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.actualView().sortOrder = .populationDescending
            }
            try await sut.inspection.inspect(after: .seconds(0.1)) { view in
                let content = try view.content()
                let countries = try content.countries()
                let firstCountry = try #require(countries.first)
                #expect(firstCountry.alpha3Code == unitedStates.alpha3Code)
                #expect(firstCountry.population == 125000000)
                container.interactors.verify()
            }
        }
    }

    @Test func populationSortUsesNameTieBreaker() async throws {
        //harness:criterion=c-population-sort-descriptor
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        let countriesWithPopulationTie = [
            ApiModel.Country(name: "United States", translations: [:], population: 125000000, flag: nil, alpha3Code: "USA"),
            ApiModel.Country(name: "Beta", translations: [:], population: 50000000, flag: nil, alpha3Code: "BET"),
            ApiModel.Country(name: "Alpha", translations: [:], population: 50000000, flag: nil, alpha3Code: "ALP")
        ]
        try await dbRepository.store(countries: countriesWithPopulationTie)
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.actualView().sortOrder = .populationDescending
            }
            try await sut.inspection.inspect(after: .seconds(0.1)) { view in
                let countryCodes = try view.content().countries().map(\.alpha3Code)
                #expect(countryCodes == ["USA", "ALP", "BET"])
                container.interactors.verify()
            }
        }
    }

    @Test func queryViewContainerEqualityIncludesSort() {
        //harness:criterion=c-query-container-equality-includes-sort,c-query-search-generic
        let alphabeticalBuilder: (String) -> Query<DBModel.Country, [DBModel.Country]> = { _ in
            Query(sort: [SortDescriptor(\DBModel.Country.name, order: .forward)])
        }
        let populationBuilder: (String) -> Query<DBModel.Country, [DBModel.Country]> = { _ in
            Query(sort: [
                SortDescriptor(\DBModel.Country.population, order: .reverse),
                SortDescriptor(\DBModel.Country.name, order: .forward)
            ])
        }
        let alphabetical = QueryViewContainer(
            searchText: "",
            sortID: CountriesList.SortOrder.alphabetical,
            builder: alphabeticalBuilder,
            results: { _, _ in }
        )
        let populationDescending = QueryViewContainer(
            searchText: "",
            sortID: CountriesList.SortOrder.populationDescending,
            builder: populationBuilder,
            results: { _, _ in }
        )
        #expect(alphabetical != populationDescending)

        let currencyBuilder: (String) -> Query<DBModel.Currency, [DBModel.Currency]> = { _ in
            Query(sort: [SortDescriptor(\DBModel.Currency.code, order: .forward)])
        }
        let currencyContainer = QueryViewContainer(
            searchText: "usd",
            sortID: "code",
            builder: currencyBuilder,
            results: { _, _ in }
        )
        let matchingCurrencyContainer = QueryViewContainer(
            searchText: "usd",
            sortID: "code",
            builder: currencyBuilder,
            results: { _, _ in }
        )
        #expect(currencyContainer == matchingCurrencyContainer)
    }

    @Test func searchAndPopulationSortCombined() async throws {
        //harness:criterion=c-search-and-population-sort-combined,c-search-unaffected-by-sort
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)
        let searchText = "n"
        let matchingCountries = dbCountries.filter { $0.name.localizedStandardContains(searchText) }
        let alphabeticalIDs = matchingCountries.sorted(by: { $0.name < $1.name }).map(\.alpha3Code)
        let populationIDs = matchingCountries
            .sorted { lhs, rhs in
                if lhs.population == rhs.population {
                    return lhs.name < rhs.name
                }
                return lhs.population > rhs.population
            }
            .map(\.alpha3Code)
        #expect(alphabeticalIDs == ["CAN", "USA"])
        #expect(populationIDs == ["USA", "CAN"])

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.actualView().searchText = searchText
                try view.actualView().sortOrder = .alphabetical
            }
            try await sut.inspection.inspect(after: .seconds(0.1)) { view in
                let alphabeticalResultIDs = try view.content().countries().map(\.alpha3Code)
                #expect(alphabeticalResultIDs == alphabeticalIDs)
            }
            try await sut.inspection.inspect { view in
                try view.actualView().sortOrder = .populationDescending
            }
            try await sut.inspection.inspect(after: .seconds(0.1)) { view in
                let populationResultIDs = try view.content().countries().map(\.alpha3Code)
                #expect(populationResultIDs == populationIDs)
                #expect(Set(populationResultIDs) == Set(alphabeticalIDs))
                #expect(populationResultIDs.count == matchingCountries.count)
                container.interactors.verify()
            }
        }
    }

    @Test func deepLinkRoutingWorksWithPopulationSort() async throws {
        //harness:criterion=c-navigation-unaffected
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.actualView().sortOrder = .populationDescending
                container.appState[\.routing.countriesList.countryCode] = "CAN"
            }
            try await sut.inspection.inspect(after: .seconds(0.1)) { view in
                let actualView = try view.actualView()
                #expect(actualView.sortOrder == .populationDescending)
                #expect(!actualView.navigationPath.isEmpty)
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
        //harness:criterion=c-push-permission-button-unaffected
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

extension InspectableView where View == ViewType.NavigationStack {
    @MainActor
    func countries() throws -> [DBModel.Country] {
        try findAll(CountryCell.self).map { try $0.actualView().country }
    }
}

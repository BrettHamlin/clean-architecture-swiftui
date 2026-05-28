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

    @Test func sortOrderDefaultsToAlphabetical() {
        //harness:criterion=c-sort-order-enum-two-cases,c-sort-order-default-alphabetical,c-sort-order-state-var-internal-access,c-sort-order-not-persisted
        let first = CountriesList(state: .loaded(()))
        let second = CountriesList(state: .loaded(()))

        #expect(first.sortOrder == .alphabetical)
        #expect(second.sortOrder == .alphabetical)
    }

    @Test func queryViewContainerTreatsSortOrderAsIdentity() {
        //harness:criterion=c-query-view-container-equality-includes-sort-order
        let builder: (String, CountriesList.SortOrder) -> Query<DBModel.Country, [DBModel.Country]> = { _, sortOrder in
            Query(sort: sortOrder.sortDescriptors)
        }
        let lhs = QueryViewContainer<DBModel.Country>(
            searchText: "Al",
            sortOrder: .alphabetical,
            builder: builder,
            results: { _, _ in })
        let rhs = QueryViewContainer<DBModel.Country>(
            searchText: "Al",
            sortOrder: .byPopulation,
            builder: builder,
            results: { _, _ in })

        #expect(lhs != rhs)
    }

    @Test func queryPipelineSortsAndFiltersCountries() async throws {
        //harness:criterion=c-query-search-accepts-sort-order-param,c-sort-order-passed-into-query-modifier,c-query-builder-alphabetical-sort-descriptor,c-query-builder-population-sort-descriptor
        //harness:criterion=c-alphabetical-sort-produces-correct-order,c-population-sort-produces-correct-order,c-search-with-alphabetical-sort-correct-subset,c-search-with-population-sort-correct-subset,c-search-behavior-unchanged
        let modelContainer = ModelContainer.mock
        try await MainDBRepository(modelContainer: modelContainer).store(countries: makeDeterministicCountries())

        let alphabetical = try await queriedCountryNames(
            searchText: "",
            sortOrder: .alphabetical,
            modelContainer: modelContainer)
        let byPopulation = try await queriedCountryNames(
            searchText: "",
            sortOrder: .byPopulation,
            modelContainer: modelContainer)
        let searchAlphabetical = try await queriedCountryNames(
            searchText: "Al",
            sortOrder: .alphabetical,
            modelContainer: modelContainer)
        let searchByPopulation = try await queriedCountryNames(
            searchText: "Al",
            sortOrder: .byPopulation,
            modelContainer: modelContainer)

        #expect(alphabetical == ["Albania", "Algeria", "Morocco", "Zimbabwe"])
        #expect(byPopulation == ["Morocco", "Algeria", "Albania", "Zimbabwe"])
        #expect(searchAlphabetical == ["Albania", "Algeria"])
        #expect(searchByPopulation == ["Algeria", "Albania"])
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

    @Test func countryRowsRemainNavigationLinksForEachSortOrder() async throws {
        //harness:criterion=c-navigation-links-unchanged
        let modelContainer = ModelContainer.mock
        try await MainDBRepository(modelContainer: modelContainer).store(countries: makeDeterministicCountries())

        for sortOrder in [CountriesList.SortOrder.alphabetical, .byPopulation] {
            let container = DIContainer(interactors: .mocked())
            let sut = CountriesList(state: .loaded(()))
            let view = sut.inject(container).modelContainer(modelContainer)

            try await ViewHosting.host(view) {
                try await sut.inspection.inspect { view in
                    try view.actualView().sortOrder = sortOrder
                }
                try await sut.inspection.inspect { view in
                    let linksCount = try view.content().findAll(ViewType.NavigationLink.self).count
                    #expect(linksCount > 0)
                    container.interactors.verify()
                }
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

    @Test func listRefreshPreservesSortOrder() async throws {
        //harness:criterion=c-pull-to-refresh-unchanged
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
                let list = try view.find(ViewType.List.self)
                try await list.callRefreshable()
                let sortOrder = try view.actualView().sortOrder
                #expect(sortOrder == .byPopulation)
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

    @Test func toolbarContainsSortToggleAndPushPermissionButtons() async throws {
        //harness:criterion=c-toolbar-sort-toggle-button-present,c-existing-push-permission-toolbar-item-preserved
        let container = DIContainer(interactors: .mocked())
        container.appState[\.permissions.push] = .notRequested
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let buttonCount = try view.findAll(ViewType.Button.self).count
                let hasSortButton = (try? view.find(button: "Sort by Population")) != nil
                let hasPushButton = (try? view.find(button: "Allow Push")) != nil

                #expect(buttonCount >= 2)
                #expect(hasSortButton)
                #expect(hasPushButton)
                container.interactors.verify()
            }
        }
    }

    @Test func sortButtonLabelReflectsSortOrder() async throws {
        //harness:criterion=c-toolbar-sort-button-label-reflects-current-sort
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let hasAlphabeticalLabel = (try? view.find(button: "Sort by Population")) != nil
                #expect(hasAlphabeticalLabel)
                try view.actualView().sortOrder = .byPopulation
            }
            try await sut.inspection.inspect { view in
                let hasPopulationLabel = (try? view.find(button: "Sort Alphabetically")) != nil
                let stillHasAlphabeticalLabel = (try? view.find(button: "Sort by Population")) != nil
                #expect(hasPopulationLabel)
                #expect(!stillHasAlphabeticalLabel)
                container.interactors.verify()
            }
        }
    }

    @Test func sortButtonTogglesSortOrderWithoutInteractorSideEffects() async throws {
        //harness:criterion=c-toolbar-sort-button-toggles-sort-order,c-toggle-sort-no-refresh-side-effect
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.find(button: "Sort by Population").tap()
                let sortOrder = try view.actualView().sortOrder
                #expect(sortOrder == .byPopulation)
                container.interactors.verify()
            }
            try await sut.inspection.inspect { view in
                try view.find(button: "Sort Alphabetically").tap()
                let sortOrder = try view.actualView().sortOrder
                #expect(sortOrder == .alphabetical)
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

// MARK: - Sort Query Helpers

private func makeDeterministicCountries() -> [ApiModel.Country] {
    [
        ApiModel.Country(name: "Zimbabwe", translations: [:], population: 200, flag: nil, alpha3Code: "ZWE"),
        ApiModel.Country(name: "Albania", translations: [:], population: 500, flag: nil, alpha3Code: "ALB"),
        ApiModel.Country(name: "Morocco", translations: [:], population: 50_000, flag: nil, alpha3Code: "MAR"),
        ApiModel.Country(name: "Algeria", translations: [:], population: 9_000, flag: nil, alpha3Code: "DZA")
    ]
}

@MainActor
private func queriedCountryNames(
    searchText: String,
    sortOrder: CountriesList.SortOrder,
    modelContainer: ModelContainer
) async throws -> [String] {
    let sut = CountriesQueryProbe(searchText: searchText, sortOrder: sortOrder)
    var names: [String] = []

    try await ViewHosting.host(sut.modelContainer(modelContainer)) {
        try await sut.inspection.inspect(after: .seconds(0.2)) { view in
            let rawText = try view.find(ViewType.Text.self).string()
            names = rawText.isEmpty ? [] : rawText.split(separator: "|").map(String.init)
        }
    }

    return names
}

private struct CountriesQueryProbe: View {

    @State private var results: [DBModel.Country] = []
    let searchText: String
    let sortOrder: CountriesList.SortOrder
    let inspection = Inspection<Self>()

    var body: some View {
        Text(results.map(\.name).joined(separator: "|"))
            .query(searchText: searchText, results: $results, sortOrder: sortOrder) { search, sortOrder in
                Query(filter: #Predicate<DBModel.Country> { country in
                    if search.isEmpty {
                        return true
                    } else {
                        return country.name.localizedStandardContains(search)
                    }
                }, sort: sortOrder.sortDescriptors)
            }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
    }
}

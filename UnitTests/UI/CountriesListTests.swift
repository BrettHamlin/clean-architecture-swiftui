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
import Foundation
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

    @Test func sortOrderDefaultsToAlphabeticalAndIsEphemeral() async throws {
        //harness:criterion=c-sort-order-state-default-alphabetical,c-sort-order-is-ephemeral-no-persistence
        let firstContainer = DIContainer(interactors: .mocked())
        let firstSut = CountriesList(state: .loaded(()))
        let firstView = firstSut.inject(firstContainer).modelContainer(ModelContainer.mock)
        try await ViewHosting.host(firstView) {
            try await firstSut.inspection.inspect { view in
                let initialSortOrder = try view.actualView().sortOrder
                #expect(initialSortOrder == .alphabetical)
                try view.actualView().sortOrder = .populationDescending
                let toggledSortOrder = try view.actualView().sortOrder
                #expect(toggledSortOrder == .populationDescending)
                firstContainer.interactors.verify()
            }
        }

        let secondContainer = DIContainer(interactors: .mocked())
        let secondSut = CountriesList(state: .loaded(()))
        let secondView = secondSut.inject(secondContainer).modelContainer(ModelContainer.mock)
        try await ViewHosting.host(secondView) {
            try await secondSut.inspection.inspect { view in
                let initialSortOrder = try view.actualView().sortOrder
                #expect(initialSortOrder == .alphabetical)
                secondContainer.interactors.verify()
            }
        }
    }

    @Test func toolbarShowsSortPickerAndPermissionsButtonTogether() async throws {
        //harness:criterion=c-sort-toggle-toolbar-coexists-with-permissions-button
        let container = DIContainer(interactors: .mocked())
        container.appState[\.permissions.push] = .notRequested
        let sut = CountriesList(state: .loaded(()))
        let view = sut.inject(container).modelContainer(ModelContainer.mock)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                _ = try view.find(ViewType.Picker.self)
                _ = try view.find(button: "Allow Push")
                container.interactors.verify()
            }
        }
    }

    @Test func sortPickerSwitchesBetweenPopulationAndAlphabeticalWithoutInteractorCalls() async throws {
        //harness:criterion=c-sort-toggle-switches-state-to-population-descending,c-sort-toggle-switches-state-back-to-alphabetical,c-sort-toggle-fires-no-reload,c-sort-toggle-fires-no-permission-request
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let view = sut.inject(container).modelContainer(ModelContainer.mock)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let picker = try view.find(ViewType.Picker.self)
                try picker.select(value: CountriesList.SortOrder.populationDescending)
                let populationSortOrder = try view.actualView().sortOrder
                #expect(populationSortOrder == .populationDescending)
                try picker.select(value: CountriesList.SortOrder.alphabetical)
                let alphabeticalSortOrder = try view.actualView().sortOrder
                #expect(alphabeticalSortOrder == .alphabetical)
                container.interactors.verify()
            }
        }
    }

    @Test func queryIdentityIncludesSortOrder() throws {
        //harness:criterion=c-query-identity-includes-sort-order
        let lhs = QueryViewContainer<DBModel.Country, CountriesList.SortOrder>(
            searchText: "",
            sortOrder: .alphabetical,
            builder: { _, sortOrder in Query(sort: sortOrder.sortDescriptors) },
            results: { _, _ in }
        )
        let rhs = QueryViewContainer<DBModel.Country, CountriesList.SortOrder>(
            searchText: "",
            sortOrder: .populationDescending,
            builder: { _, sortOrder in Query(sort: sortOrder.sortDescriptors) },
            results: { _, _ in }
        )
        #expect(lhs != rhs)
    }

    @Test func alphabeticalQueryOrdersResultsByName() async throws {
        //harness:criterion=c-query-descriptor-alphabetical-uses-name-sort
        let countries = [
            ApiModel.Country(name: "Zambia", translations: [:], population: 20, flag: nil, alpha3Code: "ZMB"),
            ApiModel.Country(name: "Argentina", translations: [:], population: 30, flag: nil, alpha3Code: "ARG"),
            ApiModel.Country(name: "Brazil", translations: [:], population: 10, flag: nil, alpha3Code: "BRA")
        ]
        let modelContainer = try await seededModelContainer(countries)
        let sut = CountryQueryHarness(searchText: "", sortOrder: .alphabetical)
        try await ViewHosting.host(sut.modelContainer(modelContainer)) {
            try await sut.inspection.inspect { view in
                let names = try view.actualView().results.map(\.name)
                #expect(names == names.sorted())
                #expect(names == ["Argentina", "Brazil", "Zambia"])
            }
        }
    }

    @Test func populationQueryOrdersResultsByDescendingPopulation() async throws {
        //harness:criterion=c-query-descriptor-population-uses-reverse-sort,c-population-sort-highest-population-first
        let countries = [
            ApiModel.Country(name: "Low", translations: [:], population: 1, flag: nil, alpha3Code: "LOW"),
            ApiModel.Country(name: "High", translations: [:], population: 100, flag: nil, alpha3Code: "HIG"),
            ApiModel.Country(name: "Middle", translations: [:], population: 50, flag: nil, alpha3Code: "MID")
        ]
        let modelContainer = try await seededModelContainer(countries)
        let sut = CountryQueryHarness(searchText: "", sortOrder: .populationDescending)
        try await ViewHosting.host(sut.modelContainer(modelContainer)) {
            try await sut.inspection.inspect { view in
                let populations = try view.actualView().results.map(\.population)
                let firstPopulation = try #require(populations.first)
                #expect(populations == populations.sorted(by: >))
                #expect(firstPopulation == 100)
            }
        }
    }

    @Test func populationQueryRespectsSearchFilter() async throws {
        //harness:criterion=c-search-filter-respected-in-population-sort
        let countries = [
            ApiModel.Country(name: "Alabama", translations: [:], population: 5, flag: nil, alpha3Code: "ALA"),
            ApiModel.Country(name: "Alaska", translations: [:], population: 10, flag: nil, alpha3Code: "ALS"),
            ApiModel.Country(name: "Brazil", translations: [:], population: 100, flag: nil, alpha3Code: "BRA")
        ]
        let modelContainer = try await seededModelContainer(countries)
        let sut = CountryQueryHarness(searchText: "Al", sortOrder: .populationDescending)
        try await ViewHosting.host(sut.modelContainer(modelContainer)) {
            try await sut.inspection.inspect { view in
                let results = try view.actualView().results
                #expect(results.map(\.name) == ["Alaska", "Alabama"])
                #expect(results.allSatisfy { $0.name.localizedStandardContains("Al") })
                #expect(results.map(\.population) == results.map(\.population).sorted(by: >))
            }
        }
    }

    @Test func modelContainerInitializesWithCountrySchema() throws {
        //harness:criterion=c-persistence-schema-unchanged
        _ = ModelContainer.mock
    }

    private func seededModelContainer(_ countries: [ApiModel.Country]) async throws -> ModelContainer {
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: countries)
        return modelContainer
    }
}

@Suite struct LocalizationTests {

    @Test func countryLocalizedName() {
        let sut = DBModel.Country(name: "Abc", translations: ["fr": "Xyz"], population: 0, flag: nil, alpha3Code: "")
        let locale = Locale(identifier: "fr")
        #expect(sut.name(locale: locale) == "Xyz")
    }

    @Test func sortLabelHasRequiredLocalizations() throws {
        //harness:criterion=c-localised-strings-sort-label-present
        try assertLocalizedString("Sort", locales: ["en", "de", "ja"])
    }

    @Test func nameLabelHasRequiredLocalizations() throws {
        //harness:criterion=c-localised-strings-name-label-present
        try assertLocalizedString("Name", locales: ["en", "de", "ja"])
    }

    @Test func populationLabelHasRequiredLocalizations() throws {
        //harness:criterion=c-localised-strings-population-label-present
        try assertLocalizedString("Population", locales: ["en", "de", "ja"])
    }

    private func assertLocalizedString(_ key: String, locales: [String]) throws {
        let fileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("CountriesSwiftUI/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: fileURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: Any])
        let entry = try #require(strings[key] as? [String: Any])
        let localizations = try #require(entry["localizations"] as? [String: Any])

        for locale in locales {
            let localizedEntry = localizations[locale] ?? (locale == "en" ? localizations["base"] : nil)
            let localization = try #require(localizedEntry as? [String: Any])
            let stringUnit = try #require(localization["stringUnit"] as? [String: Any])
            let value = try #require(stringUnit["value"] as? String)
            #expect(!value.isEmpty)
        }
    }
}

private struct CountryQueryHarness: View {
    @State var results: [DBModel.Country] = []
    let searchText: String
    let sortOrder: CountriesList.SortOrder
    let inspection = Inspection<Self>()

    var body: some View {
        Text("Query")
            .query(searchText: searchText, sortOrder: sortOrder, results: $results) { search, sortOrder in
                Query(filter: #Predicate<DBModel.Country> { country in
                    if search.isEmpty {
                        return true
                    } else {
                        return country.name.localizedStandardContains(search)
                    }
                }, sort: sortOrder.sortDescriptors)
            }
            .onReceive(inspection.notice) { self.inspection.visit(self, $0) }
    }
}

// MARK: - CountriesList inspection helper

extension InspectableView where View == ViewType.View<CountriesList> {
    func content() throws -> InspectableView<ViewType.NavigationStack> {
        return try implicitAnyView().navigationStack()
    }
}

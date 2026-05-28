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

    @Test func favoritesToolbarButtonIsPresent() async throws {
        // harness:criterion=c-countries-list-toolbar-filter-button-present,c-countries-list-tests-toolbar-button-present
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect(after: .seconds(0.2)) { view in
                let buttons = view.favoriteFilterButtons()
                #expect(buttons.count == 1)
                container.interactors.verify()
            }
        }
    }

    @Test func favoritesToolbarButtonUsesShowFavoritesLabel() async throws {
        // harness:criterion=c-countries-list-toolbar-filter-button-present,c-countries-list-tests-toolbar-button-present
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect(after: .seconds(0.2)) { view in
                let button = try view.favoriteFilterButton()
                #expect(throws: Never.self) {
                    try button.labelView().find(text: "Show Favorites")
                }
                container.interactors.verify()
            }
        }
    }

    @Test func favoritesToolbarButtonTogglesFilterState() async throws {
        // harness:criterion=c-countries-list-toolbar-toggle-changes-state,c-countries-list-tests-filter-toggle-state
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let view = sut.inject(container).modelContainer(modelContainer)
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect(after: .seconds(0.2)) { view in
                #expect(try view.actualView().showFavoritesOnly == false)
                try view.favoriteFilterButton().tap()
            }
            try await sut.inspection.inspect { view in
                #expect(try view.actualView().showFavoritesOnly == true)
                try view.favoriteFilterButton().tap()
            }
            try await sut.inspection.inspect { view in
                #expect(try view.actualView().showFavoritesOnly == false)
                container.interactors.verify()
            }
        }
    }

    @Test func queryViewContainerEqualityIncludesFavoritesFilter() throws {
        // harness:criterion=c-query-view-container-equality-includes-filter
        let lhs = QueryViewContainer<DBModel.Country>(
            searchText: "abc",
            showFavoritesOnly: false,
            builder: { _, _ in Query(sort: \DBModel.Country.name) },
            results: { _, _ in })
        let rhs = QueryViewContainer<DBModel.Country>(
            searchText: "abc",
            showFavoritesOnly: true,
            builder: { _, _ in Query(sort: \DBModel.Country.name) },
            results: { _, _ in })

        #expect(lhs != rhs)
    }

    @Test func favoritesFilterShowsOnlyFavoritedCountries() async throws {
        // harness:criterion=c-predicate-filters-favorites-when-active
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let favorite = apiCountries[1]
        try await dbRepository.setFavorite(alpha3Code: favorite.alpha3Code, isFavorite: true)
        let view = sut.inject(container).modelContainer(modelContainer)

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect(after: .seconds(0.2)) { view in
                try view.actualView().showFavoritesOnly = true
            }
            try await sut.inspection.inspect(after: .seconds(0.2)) { view in
                let cells = try view.content().findAll(CountryCell.self).map { try $0.actualView().country }
                let allCellsAreFavorites = cells.allSatisfy(\.isFavorite)
                #expect(cells.count == 1)
                #expect(cells.first?.alpha3Code == favorite.alpha3Code)
                #expect(allCellsAreFavorites)
                container.interactors.verify()
            }
        }
    }

    @Test func inactiveFavoritesFilterShowsAllCountries() async throws {
        // harness:criterion=c-predicate-returns-all-when-filter-inactive
        let container = DIContainer(interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        try await dbRepository.setFavorite(alpha3Code: apiCountries[1].alpha3Code, isFavorite: true)
        let view = sut.inject(container).modelContainer(modelContainer)

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect(after: .seconds(0.2)) { view in
                let cells = try view.content().findAll(CountryCell.self).map { try $0.actualView().country }
                let containsFavorite = cells.contains(where: \.isFavorite)
                let containsNonFavorite = cells.contains { !$0.isFavorite }
                #expect(cells.count == apiCountries.count)
                #expect(containsFavorite)
                #expect(containsNonFavorite)
                container.interactors.verify()
            }
        }
    }

    @Test func deepLinkRoutesToCountryHiddenByFavoritesFilter() async throws {
        // harness:criterion=c-deeplink-routing-bypasses-favorites-filter,c-countries-list-tests-deeplink-not-broken-by-filter
        let store = Store(AppState())
        let container = DIContainer(appState: store, interactors: .mocked())
        let sut = CountriesList(state: .loaded(()))
        let modelContainer = ModelContainer.mock
        let dbRepository = MainDBRepository(modelContainer: modelContainer)
        try await dbRepository.store(countries: apiCountries)
        let hiddenByFavoritesFilter = apiCountries[0]
        try await dbRepository.setFavorite(alpha3Code: apiCountries[1].alpha3Code, isFavorite: true)
        let view = sut.inject(container).modelContainer(modelContainer)

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect(after: .seconds(0.2)) { view in
                try view.actualView().showFavoritesOnly = true
            }
            try await sut.inspection.inspect(after: .seconds(0.2)) { view in
                #expect(try view.actualView().showFavoritesOnly == true)
                store[\.routing.countriesList.countryCode] = hiddenByFavoritesFilter.alpha3Code
            }
            try await sut.inspection.inspect(after: .seconds(0.5)) { view in
                #expect(try view.actualView().navigationPath.isEmpty == false)
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

    func favoriteFilterButtons() -> [InspectableView<ViewType.Button>] {
        return findAll(ViewType.Button.self) {
            try $0.accessibilityIdentifier() == "showFavoritesOnlyButton"
        }
    }

    func favoriteFilterButton() throws -> InspectableView<ViewType.Button> {
        return try #require(favoriteFilterButtons().first)
    }
}

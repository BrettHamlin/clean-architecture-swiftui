//
//  CountryDetailsTests.swift
//  UnitTests
//
//  Created by OpenAI on 27.05.2026.
//

import Testing
import ViewInspector
@testable import CountriesSwiftUI

@MainActor
@Suite struct CountryDetailsTests {

    @Test func favoriteButtonIsPresent() async throws {
        // harness:criterion=c-country-details-toggle-button-present
        let country = country(isFavorite: false)
        let sut = CountryDetails(country: country, details: .loaded(details(for: country)))
        let container = DIContainer(interactors: .mocked())

        try await ViewHosting.host(sut.inject(container)) {
            try await sut.inspection.inspect { view in
                let buttons = view.favoriteButtons()
                #expect(buttons.count == 1)
                container.interactors.verify()
            }
        }
    }

    @Test func favoriteButtonReflectsFavoritedCountry() async throws {
        // harness:criterion=c-country-details-toggle-reflects-isfavorite-true
        let country = country(isFavorite: true)
        let sut = CountryDetails(country: country, details: .loaded(details(for: country)))
        let container = DIContainer(interactors: .mocked())

        try await ViewHosting.host(sut.inject(container)) {
            try await sut.inspection.inspect { view in
                let button = try view.favoriteButton()
                #expect(throws: Never.self) {
                    try button.labelView().find(text: "Remove from Favorites")
                }
                container.interactors.verify()
            }
        }
    }

    @Test func favoriteButtonReflectsUnfavoritedCountry() async throws {
        // harness:criterion=c-country-details-toggle-reflects-isfavorite-false
        let country = country(isFavorite: false)
        let sut = CountryDetails(country: country, details: .loaded(details(for: country)))
        let container = DIContainer(interactors: .mocked())

        try await ViewHosting.host(sut.inject(container)) {
            try await sut.inspection.inspect { view in
                let button = try view.favoriteButton()
                #expect(throws: Never.self) {
                    try button.labelView().find(text: "Add to Favorites")
                }
                container.interactors.verify()
            }
        }
    }

    @Test func tappingFavoriteButtonCallsInteractor() async throws {
        // harness:criterion=c-country-details-toggle-calls-interactor
        let country = country(isFavorite: false)
        let sut = CountryDetails(country: country, details: .loaded(details(for: country)))
        let container = DIContainer(interactors: .mocked(countries: [
            .toggleFavorite(country: country),
        ]))

        try await ViewHosting.host(sut.inject(container)) {
            try await sut.inspection.inspect { view in
                try view.favoriteButton().tap()
            }
            try await sut.inspection.inspect(after: .seconds(0.2)) { _ in
                container.interactors.verify()
            }
        }
    }

    private func country(isFavorite: Bool) -> DBModel.Country {
        DBModel.Country(
            name: isFavorite ? "Favorited" : "Unfavorited",
            translations: [:],
            population: 1,
            alpha3Code: isFavorite ? "FVD" : "UFD",
            isFavorite: isFavorite)
    }

    private func details(for country: DBModel.Country) -> DBModel.CountryDetails {
        DBModel.CountryDetails(
            alpha3Code: country.alpha3Code,
            capital: "Capital",
            currencies: [],
            neighbors: [])
    }
}

private extension InspectableView where View == ViewType.View<CountryDetails> {
    func favoriteButtons() -> [InspectableView<ViewType.Button>] {
        return findAll(ViewType.Button.self) {
            try $0.accessibilityIdentifier() == "favoriteCountryButton"
        }
    }

    func favoriteButton() throws -> InspectableView<ViewType.Button> {
        return try #require(favoriteButtons().first)
    }
}

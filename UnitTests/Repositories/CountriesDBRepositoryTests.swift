//
//  CountriesDBRepositoryTests.swift
//  UnitTests
//
//  Created by Alexey Naumov on 19.04.2020.
//  Copyright © 2020 Alexey Naumov. All rights reserved.
//

import Testing
import SwiftData
import Foundation
@testable import CountriesSwiftUI

@MainActor
@Suite struct CountriesDBRepositoryTests {

    let container: ModelContainer
    let sut: CountriesDBRepository

    init() {
        container = .mock
        sut = MainDBRepository(modelContainer: container)
    }

    @Test func storeCountries() async throws {
        let countries = ApiModel.Country.mockedData
        try await sut.store(countries: countries)
        let results = try container.mainContext
            .fetch(FetchDescriptor<DBModel.Country>())
        #expect(results.count == countries.count)
    }

    @Test func countryDefaultsToNotFavorite() async throws {
        // harness:criterion=c-country-model-isfavorite-property
        let country = DBModel.Country(
            name: "Default Favorite Test",
            translations: [:],
            population: 1,
            alpha3Code: "DFT")
        container.mainContext.insert(country)
        try container.mainContext.save()

        let stored = try fetchCountry(alpha3Code: country.alpha3Code)
        #expect(stored.isFavorite == false)
    }

    @Test func setFavoriteSetsTrue() async throws {
        // harness:criterion=c-main-db-repo-setfavorite-sets-true,c-db-repo-tests-set-favorite
        let country = DBModel.Country(
            name: "Favorite Test",
            translations: [:],
            population: 1,
            alpha3Code: "FAV",
            isFavorite: false)
        container.mainContext.insert(country)
        try container.mainContext.save()

        try await sut.setFavorite(alpha3Code: country.alpha3Code, isFavorite: true)

        let stored = try fetchCountry(alpha3Code: country.alpha3Code)
        #expect(stored.isFavorite == true)
    }

    @Test func setFavoriteSetsFalse() async throws {
        // harness:criterion=c-main-db-repo-setfavorite-sets-false,c-db-repo-tests-unset-favorite
        let country = DBModel.Country(
            name: "Unfavorite Test",
            translations: [:],
            population: 1,
            alpha3Code: "UNF",
            isFavorite: true)
        container.mainContext.insert(country)
        try container.mainContext.save()

        try await sut.setFavorite(alpha3Code: country.alpha3Code, isFavorite: false)

        let stored = try fetchCountry(alpha3Code: country.alpha3Code)
        #expect(stored.isFavorite == false)
    }

    @Test func storeCountriesPreservesFavoriteTrue() async throws {
        // harness:criterion=c-store-countries-preserves-isfavorite,c-db-repo-tests-upsert-preserves-favorite
        let apiCountry = ApiModel.Country(
            name: "Updated Favorite",
            translations: [:],
            population: 42,
            flag: nil,
            alpha3Code: "UPT")
        let storedCountry = DBModel.Country(
            name: "Original Favorite",
            translations: [:],
            population: 1,
            alpha3Code: apiCountry.alpha3Code,
            isFavorite: true)
        container.mainContext.insert(storedCountry)
        try container.mainContext.save()

        try await sut.store(countries: [apiCountry])

        let stored = try fetchCountry(alpha3Code: apiCountry.alpha3Code)
        #expect(stored.name == apiCountry.name)
        #expect(stored.isFavorite == true)
    }

    @Test func storeCountriesPreservesFavoriteFalse() async throws {
        // harness:criterion=c-store-countries-preserves-isfavorite-false
        let apiCountry = ApiModel.Country(
            name: "Updated Non Favorite",
            translations: [:],
            population: 42,
            flag: nil,
            alpha3Code: "UPF")
        let storedCountry = DBModel.Country(
            name: "Original Non Favorite",
            translations: [:],
            population: 1,
            alpha3Code: apiCountry.alpha3Code,
            isFavorite: false)
        container.mainContext.insert(storedCountry)
        try container.mainContext.save()

        try await sut.store(countries: [apiCountry])

        let stored = try fetchCountry(alpha3Code: apiCountry.alpha3Code)
        #expect(stored.name == apiCountry.name)
        #expect(stored.isFavorite == false)
    }

    @Test func storeCountryDetails() async throws {
        let country = ApiModel.Country.mockedData[0]
        let details = ApiModel.CountryDetails.mockedData[0]
        try await sut.store(countryDetails: details, for: country.dbModel())
        let results = try container.mainContext
            .fetch(FetchDescriptor<DBModel.CountryDetails>())
        let stored = try #require(results.first)
        #expect(stored.capital == details.capital)
        #expect(stored.currencies.count == details.currencies.count)
    }

    @Test func countryDetailsForCountry() async throws {
        let country = ApiModel.Country.mockedData[0].dbModel()
        let details = ApiModel.CountryDetails.mockedData[0]
        try await sut.store(countryDetails: details, for: country)
        let stored = try #require(try await sut.countryDetails(for: country))
        #expect(stored.capital == details.capital)
        #expect(stored.currencies.count == details.currencies.count)
    }

    private func fetchCountry(alpha3Code: String) throws -> DBModel.Country {
        let descriptor = FetchDescriptor<DBModel.Country>(predicate: #Predicate {
            $0.alpha3Code == alpha3Code
        })
        return try #require(try container.mainContext.fetch(descriptor).first)
    }
}

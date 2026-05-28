//
//  MockedDBRepositories.swift
//  UnitTests
//
//  Created by Alexey Naumov on 18.04.2020.
//  Copyright © 2020 Alexey Naumov. All rights reserved.
//

import SwiftData
@testable import CountriesSwiftUI

// MARK: - CountriesWebRepository

final class MockedCountriesDBRepository: Mock, CountriesDBRepository {
    
    enum Action: Equatable {
        case fetchCountryDetails(DBModel.Country)
        case storeCountries([ApiModel.Country])
        case storeDetails(ApiModel.CountryDetails, country: DBModel.Country)
        case setFavorite(alpha3Code: String, isFavorite: Bool)
    }
    var actions = MockActions<Action>(expected: [])

    var storeCountriesResults: [Result<Void, Error>] = []
    var storeCountryDetailsResults: [Result<Void, Error>] = []
    var countryDetailsResults: [Result<DBModel.CountryDetails?, Error>] = []
    var setFavoriteResults: [Result<Void, Error>] = [.success(())]

    // MARK: - API

    @MainActor
    func countryDetails(for country: DBModel.Country) async throws -> DBModel.CountryDetails? {
        register(.fetchCountryDetails(country))
        guard !countryDetailsResults.isEmpty else { throw MockError.valueNotSet }
        return try countryDetailsResults.removeFirst().get()
    }

    func store(countries: [ApiModel.Country]) async throws {
        register(.storeCountries(countries))
        guard !storeCountriesResults.isEmpty else { throw MockError.valueNotSet }
        try storeCountriesResults.removeFirst().get()
    }

    func store(countryDetails: ApiModel.CountryDetails, for country: DBModel.Country) async throws {
        register(.storeDetails(countryDetails, country: country))
        guard !storeCountryDetailsResults.isEmpty else { throw MockError.valueNotSet }
        try storeCountryDetailsResults.removeFirst().get()
    }

    func setFavorite(alpha3Code: String, isFavorite: Bool) async throws {
        register(.setFavorite(alpha3Code: alpha3Code, isFavorite: isFavorite))
        guard !setFavoriteResults.isEmpty else { throw MockError.valueNotSet }
        try setFavoriteResults.removeFirst().get()
    }
}

extension ModelContainer {

    static var mock: ModelContainer {
        try! appModelContainer(inMemoryOnly: true, isStub: false)
    }
}

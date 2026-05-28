//
//  CountriesInteractor.swift
//  CountriesSwiftUI
//
//  Created by Alexey on 7/11/24.
//  Copyright © 2024 Alexey Naumov. All rights reserved.
//

protocol CountriesInteractor {
    func refreshCountriesList() async throws
    func loadCountryDetails(country: DBModel.Country, forceReload: Bool) async throws -> DBModel.CountryDetails
    func toggleFavorite(country: DBModel.Country) async throws
}

struct RealCountriesInteractor: CountriesInteractor {

    let webRepository: CountriesWebRepository
    let dbRepository: CountriesDBRepository

    func refreshCountriesList() async throws {
        let apiCountries = try await webRepository.countries()
        try await dbRepository.store(countries: apiCountries)
    }

    func loadCountryDetails(
        country: DBModel.Country, forceReload: Bool
    ) async throws -> DBModel.CountryDetails {
        if !forceReload,
           let stored = try? await dbRepository.countryDetails(for: country) {
            return stored
        }
        let details = try await webRepository.details(country: country)
        try await dbRepository.store(countryDetails: details, for: country)
        guard let stored = try? await dbRepository.countryDetails(for: country) else {
            throw ValueIsMissingError()
        }
        return stored
    }

    func toggleFavorite(country: DBModel.Country) async throws {
        try await dbRepository.setFavorite(alpha3Code: country.alpha3Code, isFavorite: !country.isFavorite)
    }
}

struct StubCountriesInteractor: CountriesInteractor {

    func refreshCountriesList() async throws {
    }

    func loadCountryDetails(country: DBModel.Country, forceReload: Bool) async throws -> DBModel.CountryDetails {
        throw ValueIsMissingError()
    }

    func toggleFavorite(country: DBModel.Country) async throws {
    }
}

//
//  CountriesDBRepository.swift
//  CountriesSwiftUI
//
//  Created by Alexey on 7/11/24.
//  Copyright © 2024 Alexey Naumov. All rights reserved.
//

import SwiftData
import Foundation

protocol CountriesDBRepository {
    @MainActor
    func countryDetails(for country: DBModel.Country) async throws -> DBModel.CountryDetails?
    func store(countries: [ApiModel.Country]) async throws
    func store(countryDetails: ApiModel.CountryDetails, for country: DBModel.Country) async throws
    func setFavorite(alpha3Code: String, isFavorite: Bool) async throws
}

extension MainDBRepository: CountriesDBRepository {

    @MainActor
    func countryDetails(for country: DBModel.Country) async throws -> DBModel.CountryDetails? {
        let alpha3Code = country.alpha3Code
        let fetchDescriptor = FetchDescriptor(predicate: #Predicate<DBModel.CountryDetails> {
            $0.alpha3Code == alpha3Code
        })
        return try modelContainer.mainContext.fetch(fetchDescriptor).first
    }

    func store(countries: [ApiModel.Country]) async throws {
        try modelContext.transaction {
            for country in countries {
                let alpha3Code = country.alpha3Code
                let fetchDescriptor = FetchDescriptor(predicate: #Predicate<DBModel.Country> {
                    $0.alpha3Code == alpha3Code
                })
                if let stored = try modelContext.fetch(fetchDescriptor).first {
                    stored.update(with: country)
                } else {
                    modelContext.insert(country.dbModel())
                }
            }
        }
    }

    func store(countryDetails: ApiModel.CountryDetails, for country: DBModel.Country) async throws {
        let alpha3Code = country.alpha3Code
        try modelContext.transaction {
            let currencies = countryDetails.currencies.map { $0.dbModel() }
            let neighborsFetch = FetchDescriptor(predicate: #Predicate<DBModel.Country> { countryDBModel in
                countryDetails.borders?.contains(countryDBModel.alpha3Code) == true
            })
            let neighbors = try modelContext.fetch(neighborsFetch)
            currencies.forEach {
                modelContext.insert($0)
            }
            let object = DBModel.CountryDetails(
                alpha3Code: alpha3Code,
                capital: countryDetails.capital,
                currencies: currencies,
                neighbors: neighbors)
            modelContext.insert(object)
        }
    }

    func setFavorite(alpha3Code: String, isFavorite: Bool) async throws {
        try modelContext.transaction {
            let fetchDescriptor = FetchDescriptor(predicate: #Predicate<DBModel.Country> {
                $0.alpha3Code == alpha3Code
            })
            guard let country = try modelContext.fetch(fetchDescriptor).first else {
                throw ValueIsMissingError()
            }
            country.isFavorite = isFavorite
        }
    }
}

internal extension ApiModel.Country {
    func dbModel() -> DBModel.Country {
        return .init(name: name, translations: translations,
                     population: population, flag: flag,
                     alpha3Code: alpha3Code)
    }
}

private extension DBModel.Country {
    func update(with country: ApiModel.Country) {
        name = country.name
        translations = country.translations
        population = country.population
        flag = country.flag
    }
}

internal extension ApiModel.Currency {
    func dbModel() -> DBModel.Currency {
        return .init(code: code, symbol: symbol, name: name)
    }
}

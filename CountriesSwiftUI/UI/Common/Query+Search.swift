//
//  Query+Search.swift
//  CountriesSwiftUI
//
//  Created by Alexey on 8/11/24.
//  Copyright © 2024 Alexey Naumov. All rights reserved.
//

import SwiftUI
import SwiftData

extension View {
    /**
     Allows for recreating the @Query each time a searchText changes
     */
    func query<T: PersistentModel>(
        searchText: String,
        results: Binding<[T]>,
        _ builder: @escaping (String) -> Query<T, [T]>
    ) -> some View {
        query(searchText: searchText, updateTrigger: EmptyQueryTrigger(), results: results, builder)
    }

    /**
     Allows for recreating the @Query each time a searchText or query-driving state changes
     */
    func query<T: PersistentModel, UpdateTrigger: Equatable>(
        searchText: String,
        updateTrigger: UpdateTrigger,
        results: Binding<[T]>,
        _ builder: @escaping (String) -> Query<T, [T]>
    ) -> some View {
        background {
            QueryViewContainer(
                searchText: searchText,
                updateTrigger: updateTrigger,
                builder: builder
            ) { _, values in
                results.wrappedValue = values
            }.equatable()
        }
    }
}

private struct EmptyQueryTrigger: Equatable {}

/**
 This view serves as a "shield" over QueryView to avoid dual query
 */
private struct QueryViewContainer<T: PersistentModel, UpdateTrigger: Equatable>: View, Equatable {

    let searchText: String
    let updateTrigger: UpdateTrigger
    let builder: (String) -> Query<T, [T]>
    let results: ([T], [T]) -> Void

    var body: some View {
        QueryView(query: builder(searchText), results: results)
    }

    static func == (
        lhs: QueryViewContainer<T, UpdateTrigger>,
        rhs: QueryViewContainer<T, UpdateTrigger>
    ) -> Bool {
        return lhs.searchText == rhs.searchText && lhs.updateTrigger == rhs.updateTrigger
    }
}

private struct QueryView<T: PersistentModel>: View {

    @Query var query: [T]
    let results: ([T], [T]) -> Void

    init(query: Query<T, [T]>, results: @escaping ([T], [T]) -> Void) {
        _query = query
        self.results = results
    }

    var body: some View {
        Rectangle()
            .hidden()
            .onChange(of: query, initial: true, results)
    }
}

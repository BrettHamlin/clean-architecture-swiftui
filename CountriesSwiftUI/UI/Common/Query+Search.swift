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
        query(searchText: searchText, sortKey: false, results: results, builder)
    }

    /**
     Allows for recreating the @Query each time a searchText or sort key changes
     */
    func query<T: PersistentModel, SortKey: Equatable>(
        searchText: String,
        sortKey: SortKey,
        results: Binding<[T]>,
        _ builder: @escaping (String) -> Query<T, [T]>
    ) -> some View {
        background {
            QueryViewContainer(searchText: searchText, sortKey: sortKey, builder: builder) { _, values in
                results.wrappedValue = values
            }.equatable()
        }
    }
}

/**
 This view serves as a "shield" over QueryView to avoid dual query
 */
struct QueryViewContainer<T: PersistentModel, SortKey: Equatable>: View, Equatable {

    let searchText: String
    let sortKey: SortKey
    let builder: (String) -> Query<T, [T]>
    let results: ([T], [T]) -> Void

    var body: some View {
        QueryView(query: builder(searchText), results: results)
    }

    static func == (lhs: QueryViewContainer<T, SortKey>, rhs: QueryViewContainer<T, SortKey>) -> Bool {
        return lhs.searchText == rhs.searchText && lhs.sortKey == rhs.sortKey
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

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
     Allows for recreating the @Query each time query inputs change
     */
    func query<T: PersistentModel, SortOrder: Equatable>(
        searchText: String,
        sortOrder: SortOrder,
        results: Binding<[T]>,
        _ builder: @escaping (String, SortOrder) -> Query<T, [T]>
    ) -> some View {
        background {
            QueryViewContainer(searchText: searchText, sortOrder: sortOrder, builder: builder) { _, values in
                results.wrappedValue = values
            }.equatable()
        }
    }
}

/**
 This view serves as a "shield" over QueryView to avoid dual query
 */
struct QueryViewContainer<T: PersistentModel, SortOrder: Equatable>: View, Equatable {

    let searchText: String
    let sortOrder: SortOrder
    let builder: (String, SortOrder) -> Query<T, [T]>
    let results: ([T], [T]) -> Void

    var body: some View {
        QueryView(query: builder(searchText, sortOrder), results: results)
    }

    static func == (lhs: QueryViewContainer<T, SortOrder>, rhs: QueryViewContainer<T, SortOrder>) -> Bool {
        return lhs.searchText == rhs.searchText && lhs.sortOrder == rhs.sortOrder
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

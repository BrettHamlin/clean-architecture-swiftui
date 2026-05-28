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
     Allows for recreating the @Query each time a searchText or sort mode changes
     */
    func query<T: PersistentModel>(
        searchText: String,
        results: Binding<[T]>,
        _ builder: @escaping (String) -> Query<T, [T]>
    ) -> some View {
        query(searchText: searchText, sortMode: false, results: results) { search, _ in
            builder(search)
        }
    }

    func query<T: PersistentModel, SortMode: Equatable>(
        searchText: String,
        results: Binding<[T]>,
        sortMode: SortMode,
        _ builder: @escaping (String, SortMode) -> Query<T, [T]>
    ) -> some View {
        query(searchText: searchText, sortMode: sortMode, results: results, builder)
    }

    func query<T: PersistentModel, SortMode: Equatable>(
        searchText: String,
        sortMode: SortMode,
        results: Binding<[T]>,
        _ builder: @escaping (String, SortMode) -> Query<T, [T]>
    ) -> some View {
        background {
            QueryViewContainer(searchText: searchText, sortMode: sortMode, builder: builder) { _, values in
                results.wrappedValue = values
            }.equatable()
        }
    }
}

/**
 This view serves as a "shield" over QueryView to avoid dual query
 */
struct QueryViewContainer<T: PersistentModel, SortMode: Equatable>: View, Equatable {

    let searchText: String
    let sortMode: SortMode
    let builder: (String, SortMode) -> Query<T, [T]>
    let results: ([T], [T]) -> Void

    var body: some View {
        QueryView(query: builder(searchText, sortMode), sortMode: sortMode, results: results)
    }

    static func == (lhs: QueryViewContainer<T, SortMode>, rhs: QueryViewContainer<T, SortMode>) -> Bool {
        return lhs.searchText == rhs.searchText && lhs.sortMode == rhs.sortMode
    }
}

struct QueryView<T: PersistentModel, SortMode: Equatable>: View {

    @Query var query: [T]
    let sortMode: SortMode
    let results: ([T], [T]) -> Void

    init(query: Query<T, [T]>, sortMode: SortMode, results: @escaping ([T], [T]) -> Void) {
        _query = query
        self.sortMode = sortMode
        self.results = results
    }

    var body: some View {
        Rectangle()
            .hidden()
            .onChange(of: query, initial: true, results)
    }
}

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
        queryContainer(searchText: searchText, sort: nil, results: results) { search, _ in
            builder(search)
        }
    }

    /**
     Allows for recreating the @Query each time searchText or sort changes
     */
    func query<T: PersistentModel>(
        searchText: String,
        sort: SortDescriptor<T>,
        results: Binding<[T]>,
        _ builder: @escaping (String, SortDescriptor<T>) -> Query<T, [T]>
    ) -> some View {
        queryContainer(searchText: searchText, sort: sort, results: results) { search, sort in
            builder(search, sort!)
        }
    }

    private func queryContainer<T: PersistentModel>(
        searchText: String,
        sort: SortDescriptor<T>?,
        results: Binding<[T]>,
        _ builder: @escaping (String, SortDescriptor<T>?) -> Query<T, [T]>
    ) -> some View {
        background {
            QueryViewContainer(searchText: searchText, sort: sort, builder: builder) { _, values in
                results.wrappedValue = values
            }.equatable()
        }
    }
}

/**
 This view serves as a "shield" over QueryView to avoid dual query
 */
struct QueryViewContainer<T: PersistentModel>: View, Equatable {

    let searchText: String
    let sort: SortDescriptor<T>?
    let builder: (String, SortDescriptor<T>?) -> Query<T, [T]>
    let results: ([T], [T]) -> Void

    var body: some View {
        QueryView(query: builder(searchText, sort), results: results)
    }

    static func == (lhs: QueryViewContainer<T>, rhs: QueryViewContainer<T>) -> Bool {
        return lhs.searchText == rhs.searchText && lhs.sort == rhs.sort
    }
}

struct QueryView<T: PersistentModel>: View {

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

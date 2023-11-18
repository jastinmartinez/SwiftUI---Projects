//
//  URLSessionAdapter.swift
//  Airports
//
//  Created by Jastin on 12/11/23.
//

import Foundation

public protocol URLSessionAdapter {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionAdapter {}

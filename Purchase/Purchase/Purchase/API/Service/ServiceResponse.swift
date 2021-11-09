//
//  ServiceResponse.swift
//  Purchase
//
//  Created by Jastin on 9/11/21.
//

import Foundation

struct ServiceResponse<T> {
    var value: T?
    var error: [Error]
}


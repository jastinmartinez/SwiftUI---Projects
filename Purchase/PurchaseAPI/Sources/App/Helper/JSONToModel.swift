//
//  File.swift
//  
//
//  Created by Jastin on 7/11/21.
//

import Foundation
import Vapor

final class JSONToModel<T : Decodable> {
    
    var parse: ((_ req: Request) throws ->  T) = { try $0.content.decode(T.self) }
}

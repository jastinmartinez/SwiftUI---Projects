//
//  AccoutableSeat.swift
//  Purchase
//
//  Created by Jastin on 11/12/21.
//

import Foundation


struct AccountableSeat: Codable {
    
    let description: String
    
    let auxiliar: Int
    
    let currencyCode: Int
    
    let detail: AccoutableSeatDetail
    
}

struct AccoutableSeatDetail: Codable {
    
    let cuentaCR:String
    
    let cuentaDB:String
    
    let amountCR: Double
    
    let amountDB: Double
}

struct AccountableSeatResponse : Decodable {
    
    var id: Int
}

struct AccoubtableSeatListResponse: Decodable {
    
    let results: [AccoubtableSeatListResponseDetail]
}

struct AccoubtableSeatListResponseDetail: Decodable  {
    
    let id: Int
    
    let description: String
    
    let date: String
    
    let accountingSeatDetail: AccoutableSeatDetail
}


//
//  AccoutableSeat.swift
//  Purchase
//
//  Created by Jastin on 11/12/21.
//

import Foundation


struct AccountableSeat: Encodable {
    
    let description: String = "Asientos Contables Compras -> \(Date.now)"
    
    let auxiliar: Int = 1
    
    let currencyCode: Int = 1
    
    let detail: AccoutableSeatDetail
    
}

struct AccoutableSeatDetail: Encodable {
    
    let cuentaCR:String = "6"
    
    let cuentaDB:String = "13"
    
    let amountCR: Double
    
    let amountDB: Double
}

struct AccountableSeatResponse : Decodable {
    
    var id: Int
}



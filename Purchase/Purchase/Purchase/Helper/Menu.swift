//
//  Menu.swift
//  Purchase
//
//  Created by Jastin on 9/11/21.
//

import Foundation


struct Menu: Hashable {
    
    let name: String
    
    let Image: String
}


var Menus:[Menu] = [
    
    Menu(name: "Deparment", Image: "department"),
    Menu(name: "Measure Unit", Image: "measureunit"),
    Menu(name: "Deparment", Image: "department"),
    Menu(name: "Measure Unit", Image: "measureunit")
]

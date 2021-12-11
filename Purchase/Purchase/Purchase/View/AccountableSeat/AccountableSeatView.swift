//
//  AccountableSeatView.swift
//  Purchase
//
//  Created by Jastin on 11/12/21.
//

import SwiftUI

struct AccountableSeatView: View {
    
    @StateObject var accountableSeatController = AccountableSeatController()
    
    var body: some View {
        
        List() {
            Text("Procesadas")
                .font(.title)
                .foregroundColor(.blue)
            ForEach(accountableSeatController.auccoutableSeats, id: \.id) { accountSeat in
                
                VStack(alignment: .leading) {
                    
                    Text("Transaccion No. \(accountSeat.id)")
                    Text("Descripcion: \(accountSeat.description)")
                    Text("Fecha: \(accountSeat.date)")
                    Text("Cuenta Credito: \(accountSeat.accountingSeatDetail.cuentaCR)")
                    Text("Cuenta Debito: \(accountSeat.accountingSeatDetail.cuentaDB)")
                    Text("Debito: \(String(format: "%.2f",accountSeat.accountingSeatDetail.amountCR))")
                    Text("Credito: \(String(format: "%.2f",accountSeat.accountingSeatDetail.amountDB))")
                }
            }
        }
    }
}

struct AccountableSeatView_Previews: PreviewProvider {
    static var previews: some View {
        AccountableSeatView()
    }
}

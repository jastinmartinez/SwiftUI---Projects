//
//  MainMenu.swift
//  Purchase
//
//  Created by Jastin on 9/11/21.
//

import SwiftUI

struct MainMenuView: View {
   
    var body: some View {
        
        NavigationView {
            
            ZStack {
                
                RadialGradient(stops:[.init(color: Color(.white), location: 0.3),.init(color: Color(red: 0.1, green: 0.2, blue: 0.45), location: 0.3)], center: .top, startRadius: 100, endRadius: 700)
                    .ignoresSafeArea()
                
                HStack {
                   Spacer()
                   
                    VStack(alignment: .leading,spacing: 15) {
                        
        
                        NavigationLink(destination: PurchaseOrderListView().navigationTitle("Ordernes de Compra")) {
                            LogoView(name: "purchaseorder")
                            MenuTitle(name: "Orden de compra")
                        }
                        
                        NavigationLink(destination: ArticleListView().navigationTitle("Articulos")) {
                            LogoView(name: "article")
                            MenuTitle(name: "Articulo")
                        }
                        
                        NavigationLink(destination: ProviderListView().navigationTitle("Proveedores")) {
                            LogoView(name: "provider")
                            MenuTitle(name: "Proveedor")
                        }
                        
                        NavigationLink(destination: MeasureUnitListView().navigationTitle("Unidad de Medidas")) {
                            LogoView(name: "measureunit")
                            MenuTitle(name: "Unidad Medida")
                        }
                        
                        NavigationLink(destination: DepartmListView().navigationTitle("Departamentos")) {
                            LogoView(name: "department")
                            MenuTitle(name: "Departamento")
                        }
                    }
                    Spacer()
                    Spacer()
                    Spacer()
                    Spacer()
                    Spacer()
                    Spacer()
                    Spacer()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                   Text("Compras")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(.blue)
                        Text("Bienvenido Jastin!!").font(.headline)
                        
                    }
                }
                
            }
            .onAppear {
                
            }
        }
    }
}

struct MainMenu_Previews: PreviewProvider {
    static var previews: some View {
        MainMenuView()
    }
}

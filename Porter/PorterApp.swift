//
//  PorterApp.swift
//  Porter
//
//  Created by Eduard on 26.02.26.
//

import SwiftUI

@main
struct PorterApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}

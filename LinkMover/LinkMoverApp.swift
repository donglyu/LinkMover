//
//  LinkMoverApp.swift
//  LinkMover
//
//  Created by Leon on 2026/6/5.
//

import SwiftUI

@main
struct LinkMoverApp: App {
    @StateObject private var localization = LocalizationManager()

    var body: some Scene {
        WindowGroup {
            ContentView(localization: localization)
                .environment(\.locale, localization.strings.locale)
        }
        .windowResizability(.contentSize)
    }
}

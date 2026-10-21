//
//  fairwayvector_golfpintheoryApp.swift
//  fairwayvector-golfpintheory
//
//  Created by Joel spolen on 2026-09-28.
//

import SwiftUI

@main
struct fairwayvector_golfpintheoryApp: App {
    @StateObject private var accountSession = PinTheoryAccountSession()

    var body: some Scene {
        WindowGroup {
            PinTheoryAccountRootView(session: accountSession)
        }
    }
}

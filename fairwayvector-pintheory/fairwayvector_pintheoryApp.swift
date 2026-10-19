//
//  fairwayvector_pintheoryApp.swift
//  fairwayvector-pintheory
//
//  Created by Joel spolen on 2026-09-28.
//

import SwiftUI

@main
struct fairwayvector_pintheoryApp: App {
    @StateObject private var accountSession = PinTheoryAccountSession()

    var body: some Scene {
        WindowGroup {
            PinTheoryAccountRootView(session: accountSession)
        }
    }
}

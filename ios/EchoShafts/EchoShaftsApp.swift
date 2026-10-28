import Combine
import SwiftUI

@main
struct EchoShaftsApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = GameSession()

    var body: some View {
        ZStack {
            Color(hex: 0x140f0c).ignoresSafeArea()
            if session.save.origin == nil {
                OriginView(session: session)
            } else {
                PlayView(session: session)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { session.enterBackground() }
            if phase == .active { session.enterForeground() }
        }
        #if DEBUG
        .onAppear { AgentDriver.shared.attach(session) }
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
            AgentDriver.shared.pulse(session)
        }
        #endif
    }
}

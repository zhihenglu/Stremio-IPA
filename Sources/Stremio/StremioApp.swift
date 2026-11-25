import SwiftUI

@main
struct StremioApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea()
                .background(Color(red: 0.165, green: 0.157, blue: 0.263)) // #2a2843 Stremio 主题色
                .preferredColorScheme(.dark)
        }
    }
}

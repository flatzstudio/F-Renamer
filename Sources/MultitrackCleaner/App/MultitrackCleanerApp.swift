import SwiftUI

@main
struct MultitrackCleanerApp: App {
    @StateObject private var inputRouter = ApplicationInputRouter()
    @StateObject private var localization = AppLocalization()

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(inputRouter)
                .environmentObject(localization)
                .onOpenURL { inputRouter.receive(url: $0) }
        }
        .defaultSize(width: 720, height: 720)
        .windowResizability(.contentSize)
    }
}

import SwiftUI

@main
struct RunnerStatusApp: App {
    @StateObject private var store = RunnerStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            Image(nsImage: Octocat.image)
        }
        .menuBarExtraStyle(.window)
    }
}

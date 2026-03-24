import SwiftUI

@main
struct KitchenSurveyApp: App {
    @StateObject private var store = SurveyStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

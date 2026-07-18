import SwiftUI

// Simples Steuer-Objekt für Tab-Wechsel von außerhalb des TabView selbst,
// z.B. wenn der SmartTodoBanner im Profil direkt zu "Dateien" springen soll.
@Observable
class TabRouter {
    var selectedTab: Int = 0
}

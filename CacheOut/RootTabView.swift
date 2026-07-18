import SwiftUI

struct RootTabView: View {
    @Environment(TabRouter.self) private var tabRouter

    var body: some View {
        @Bindable var tabRouter = tabRouter

        TabView(selection: $tabRouter.selectedTab) {
            Tab(value: 0) {
                SwipeTab()
            } label: {
                Label("Swipen", systemImage: "photo.on.rectangle.angled")
                    .labelStyle(.iconOnly)
            }
            Tab(value: 1) {
                MeinLebenTab()
            } label: {
                Label("Mein Leben", systemImage: "calendar")
                    .labelStyle(.iconOnly)
            }
            Tab(value: 2) {
                NuetzlichesTab()
            } label: {
                Label("Nützliches", systemImage: "square.grid.2x2")
                    .labelStyle(.iconOnly)
            }
            Tab(value: 3) {
                FileSwipeTab()
            } label: {
                Label("Dateien", systemImage: "doc.badge.gearshape")
                    .labelStyle(.iconOnly)
            }
            Tab(value: 4) {
                ProfilTab()
            } label: {
                Label("Profil", systemImage: "person.crop.circle")
                    .labelStyle(.iconOnly)
            }
        }
    }
}
#Preview {
    RootTabView()
}

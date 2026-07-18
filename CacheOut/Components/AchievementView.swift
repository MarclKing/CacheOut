import SwiftUI

// MARK: - Erfolge: feste 2x2-Grid, KEIN Swipe

struct GoalsGrid: View {
    let goals: [AchievementDisplay]

    var body: some View {
        VStack(spacing: 16) {
            Text("Erfolge")
                .font(.subheadline).bold()
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(goals.prefix(4)) { goal in
                    GoalTile(goal: goal)
                }
            }
        }
        .padding(16)
        .background(Color(hex: "12142B"), in: RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - Größere Erfolge-Kreise, keine Kachel

private struct GoalTile: View {
    let goal: AchievementDisplay

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: goal.progress)
                    .stroke(AppTheme.linearGradient(goal.rarity.gradient), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: goal.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)

            Text(goal.title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(12)
    }
}

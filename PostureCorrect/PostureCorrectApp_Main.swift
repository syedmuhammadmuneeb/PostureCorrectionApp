//
//  PostureCorrectApp_Main.swift
//  PostureCorrect
//
//  Created by Syed Muhammad Muneeb on 01/06/26.
//

//
//  PostureCorrectApp_Main.swift
//  PostureCorrect
//
//  iOS 26 compliant UI — Coach, Workouts, Progress tabs
//  Uses native TabView with Tab() API, .glassEffect(), and iOS 26 button styles
//  All type names prefixed with "PC" to avoid conflicts with existing files.
//

import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - App Entry (rename to @main if you want this as entry point,
//         otherwise call PCRootView() from your existing PostureCorrectApp)
// ─────────────────────────────────────────────────────────────────────────────

struct PCRootView: View {
    var body: some View {
        PCMainTabView()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Main Tab View  (iOS 26 native Tab API)
// ─────────────────────────────────────────────────────────────────────────────
// In iOS 26 the TabView automatically adopts Liquid Glass on the tab bar
// when compiled with Xcode 26. Use the new Tab() API (not TabItem).
// .tabBarMinimizeBehavior(.onScrollDown) collapses the bar when scrolling down
// so the exercise camera has more screen real estate.
// ─────────────────────────────────────────────────────────────────────────────

struct PCMainTabView: View {
    var body: some View {
        TabView {
            // ── Coach (home) ────────────────────────────────────────────────
            Tab("Coach", systemImage: "figure.mind.and.body") {
                PCCoachView()
            }

            // ── Workouts ────────────────────────────────────────────────────
            Tab("Workouts", systemImage: "dumbbell") {
                PCWorkoutsView()
            }

            // ── Progress ────────────────────────────────────────────────────
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis") {
                PCProgressView()
            }

            // ── Profile ─────────────────────────────────────────────────────
            Tab("Profile", systemImage: "person.circle") {
                PCProfileView()
            }
        }
        // Collapses tab bar when user scrolls down — more room for camera
        .tabBarMinimizeBehavior(.onScrollDown)
        // iOS 26: tint controls the selected tab indicator colour
        .tint(.green)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Coach View
// ─────────────────────────────────────────────────────────────────────────────

struct PCCoachView: View {
    @ObservedObject private var store = LastExerciseStore.shared

    // Greeting helper
    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 12 { return "Good Morning," }
        if h < 17 { return "Good Afternoon," }
        return "Good Evening,"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Greeting ─────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 4) {
                        Text(greeting)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("John 👋")
                            .font(.largeTitle.bold())
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // ── Form Score Card — live from last session ───────────────
                    PCFormScoreCard(score: store.last?.formScore ?? 0,
                                   hasData: store.last != nil)
                        .padding(.horizontal)

                    // ── Continue Workout — last exercise or default Squats ─────
                    PCContinueWorkoutCard(last: store.last)
                        .padding(.horizontal)

                    // ── Recent Feedback — errors from last session ─────────────
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Recent Feedback")
                                .font(.headline)
                            Spacer()
                            if let last = store.last {
                                Text(last.exerciseName)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .glassEffect(.regular, in: Capsule())
                            }
                        }
                        .padding(.horizontal)

                        PCFeedbackList(last: store.last)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Form Score Card
// Uses .glassEffect() — the iOS 26 Liquid Glass material
// Applied to the card container so it floats above the scroll content
// ─────────────────────────────────────────────────────────────────────────────

struct PCFormScoreCard: View {
    let score:   Int
    var hasData: Bool = true

    private var ringColor: Color {
        if !hasData   { return .gray }
        if score >= 80 { return .green }
        if score >= 55 { return .yellow }
        return .red
    }
    private var scoreLabel: String {
        hasData ? "\(score)" : "—"
    }
    private var caption: String {
        guard hasData else { return "Complete an exercise to see your score." }
        if score >= 80 { return "Great job! Keep it up." }
        if score >= 55 { return "Good effort — room to improve." }
        return "Focus on form next session."
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("LAST SESSION SCORE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(scoreLabel)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(ringColor)
                    if hasData {
                        Text("/100")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Score ring
            ZStack {
                Circle()
                    .stroke(ringColor.opacity(0.2), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: hasData ? CGFloat(score) / 100 : 0)
                    .stroke(ringColor,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "waveform.path.ecg")
                    .font(.title2)
                    .foregroundStyle(ringColor)
            }
            .frame(width: 68, height: 68)
        }
        .padding(20)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Continue Workout Card
// ─────────────────────────────────────────────────────────────────────────────

struct PCContinueWorkoutCard: View {
    var last: PCLastExercise? = nil

    // Falls back to Squats when no session has been recorded yet
    private var exerciseName: String { last?.exerciseName ?? "Squats" }
    private var icon:         String { last?.icon ?? "figure.strengthtraining.functional" }
    private var iconColor:    Color  { colorFromName(last?.iconColor ?? "orange") }
    private var subtitle:     String {
        guard let l = last else { return "Side-on camera · Bodyweight" }
        return "\(l.sessionTime) · \(l.totalReps) rep\(l.totalReps == 1 ? "" : "s")"
    }

    private func colorFromName(_ name: String) -> Color {
        switch name {
        case "blue":   return .blue
        case "green":  return .green
        case "orange": return .orange
        case "red":    return .red
        case "purple": return .purple
        case "yellow": return .yellow
        case "pink":   return .pink
        case "teal":   return .teal
        case "cyan":   return .cyan
        case "mint":   return .mint
        case "indigo": return .indigo
        default:       return .orange
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(iconColor)
                .frame(width: 52, height: 52)
                .glassEffect(.regular.tint(iconColor.opacity(0.2)),
                             in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Continue Workout")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(exerciseName)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Always navigates to Squats (expand later for other exercises)
            NavigationLink(destination: SquatCameraView()) {
                Image(systemName: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 40, height: 40)
            }
            .glassEffect(.regular.tint(iconColor.opacity(0.25)).interactive(),
                         in: .circle)
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Feedback List  (driven by LastExerciseStore)
// ─────────────────────────────────────────────────────────────────────────────

struct PCFeedbackList: View {
    var last: PCLastExercise? = nil

    // Relative time helper
    private func timeAgo(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60 { return "Just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        return "\(s / 86400)d ago"
    }

    var body: some View {
        VStack(spacing: 0) {
            if let last = last, !last.feedbackItems.isEmpty {
                let items = last.feedbackItems
                ForEach(items) { item in
                    let iconName  = item.isGood ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    let iconColor: Color = item.isGood ? .green : .orange
                    let subtitle  = "\(last.exerciseName) · \(timeAgo(item.timestamp))"

                    HStack(spacing: 12) {
                        Image(systemName: iconName)
                            .font(.subheadline)
                            .foregroundStyle(iconColor)
                            .frame(width: 32, height: 32)
                            .glassEffect(
                                .regular.tint(iconColor.opacity(0.15)),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.medium))
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)

                    if item.id != items.last?.id {
                        Divider().padding(.leading, 56)
                    }
                }
            } else {
                // Placeholder when no session has been completed yet
                HStack(spacing: 12) {
                    Image(systemName: "figure.strengthtraining.functional")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .frame(width: 32, height: 32)
                        .glassEffect(.regular.tint(.secondary.opacity(0.1)),
                                     in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text("Complete an exercise to see feedback here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 14)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Workouts View
// ─────────────────────────────────────────────────────────────────────────────

struct PCWorkoutEntry: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let iconColor: Color
    let duration: String
    let category: String
    let difficulty: String
    let difficultyColor: Color
    let destination: AnyView
}

struct PCWorkoutsView: View {
    @State private var selectedFilter = "All"
    let filters = ["All", "Upper Body", "Lower Body", "Core"]

    private var workouts: [PCWorkoutEntry] {[
        .init(name: "Push-ups",        icon: "figure.core.training",    iconColor: .blue,
              duration: "10 min", category: "Upper Body",
              difficulty: "Beginner", difficultyColor: .green,
              destination: AnyView(PushupCameraView())),
        .init(name: "Squats",          icon: "figure.strengthtraining.functional",        iconColor: .orange,
              duration: "8 min",  category: "Lower Body",
              difficulty: "Beginner", difficultyColor: .green,
              destination: AnyView(SquatCameraView())),
        .init(name: "Plank",           icon: "figure.core.training",iconColor: .purple,
              duration: "6 min",  category: "Core",
              difficulty: "Beginner", difficultyColor: .green,
              destination: AnyView(PlankCameraView())),
        .init(name: "Glute Bridge",    icon: "figure.gymnastics",   iconColor: .pink,
              duration: "10 min", category: "Lower Body",
              difficulty: "Beginner", difficultyColor: .green,
              destination: AnyView(GluteBridgeCameraView())),
    ]}

    private var filtered: [PCWorkoutEntry] {
        selectedFilter == "All" ? workouts
            : workouts.filter { $0.category == selectedFilter }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // ── Filter chips ─────────────────────────────────────────
                    // iOS 26: GlassEffectContainer groups chips so they morph
                    // together when the selection changes
                    ScrollView(.horizontal, showsIndicators: false) {
                        GlassEffectContainer {
                            HStack(spacing: 8) {
                                ForEach(filters, id: \.self) { filter in
                                    Button(filter) {
                                        withAnimation(.spring(response: 0.3)) {
                                            selectedFilter = filter
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(selectedFilter == filter ? .black : .primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .glassEffect(
                                        selectedFilter == filter
                                            ? .regular.tint(.green).interactive()
                                            : .regular.interactive(),
                                        in: .capsule
                                    )
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                    }

                    // ── Workout list ─────────────────────────────────────────
                    LazyVStack(spacing: 12) {
                        ForEach(filtered) { workout in
                            NavigationLink(destination: workout.destination) {
                                PCWorkoutCard(workout: workout)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Workouts")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct PCWorkoutCard: View {
    let workout: PCWorkoutEntry

    var body: some View {
        HStack(spacing: 14) {
            // Icon badge with glass tint matching the exercise colour
            Image(systemName: workout.icon)
                .font(.title2)
                .foregroundStyle(workout.iconColor)
                .frame(width: 56, height: 56)
                .glassEffect(
                    .regular.tint(workout.iconColor.opacity(0.2)),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(workout.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Bodyweight · \(workout.duration)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Difficulty badge
                Text(workout.difficulty)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(workout.difficultyColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .glassEffect(
                        .regular.tint(workout.difficultyColor.opacity(0.2)),
                        in: Capsule()
                    )
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Progress View
// ─────────────────────────────────────────────────────────────────────────────

struct PCProgressView: View {
    let weekDays   = ["M", "T", "W", "T", "F", "S", "S"]
    let barHeights = [0.7, 0.5, 0.85, 0.4, 0.92, 0.15, 0.0]
    let todayIndex = 4

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // ── Period picker ─────────────────────────────────────────
                    HStack {
                        Spacer()
                        // iOS 26 menu button with glass
                        Menu {
                            Button("This Week",  action: {})
                            Button("This Month", action: {})
                            Button("All Time",   action: {})
                        } label: {
                            HStack(spacing: 4) {
                                Text("This Week")
                                    .font(.subheadline.weight(.medium))
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .glassEffect(.regular.interactive(), in: Capsule())
                        }
                    }
                    .padding(.horizontal)

                    // ── 2×2 stat grid ─────────────────────────────────────────
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        PCStatTile(label: "Avg Form Score",
                                   value: "88", unit: "/100",
                                   valueColor: .green, trend: "+6 vs last week")
                        PCStatTile(label: "Total Reps",
                                   value: "243", unit: "",
                                   valueColor: .primary, trend: "+18 vs last week")
                        PCStatTile(label: "Sessions",
                                   value: "5",  unit: "/6",
                                   valueColor: .primary, trend: "Goal: 6",
                                   trendColor: .orange)
                        PCStatTile(label: "Best Score",
                                   value: "98", unit: "/100",
                                   valueColor: .orange, trend: "Push-ups")
                    }
                    .padding(.horizontal)

                    // ── Weekly bar chart ──────────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Form score this week")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal)

                        HStack(alignment: .bottom, spacing: 8) {
                            ForEach(Array(weekDays.enumerated()), id: \.offset) { idx, day in
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(idx == todayIndex ? Color.green : Color.green.opacity(0.25))
                                        .frame(height: max(6, CGFloat(barHeights[idx]) * 60))
                                    Text(day)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(idx == todayIndex ? .green : .secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 14)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.horizontal)
                    }

                    // ── Top exercises ─────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Top exercises")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal)
                            .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            PCExerciseScoreRow(name: "Push-ups",        score: 92, trending: true)
                            Divider().padding(.leading, 16)
                            PCExerciseScoreRow(name: "Plank",           score: 91, trending: true)
                            Divider().padding(.leading, 16)
                            PCExerciseScoreRow(name: "Squats",          score: 87, trending: true)
                            Divider().padding(.leading, 16)
                            PCExerciseScoreRow(name: "Lunges",          score: 85, trending: false)
                        }
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top, 8)
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct PCStatTile: View {
    let label:      String
    let value:      String
    let unit:       String
    let valueColor: Color
    let trend:      String
    var trendColor: Color = .green

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(valueColor)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(trend)
                .font(.caption2)
                .foregroundStyle(trendColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct PCExerciseScoreRow: View {
    let name:     String
    let score:    Int
    let trending: Bool

    var body: some View {
        HStack {
            Text(name)
                .font(.subheadline)
            Spacer()
            HStack(spacing: 4) {
                Text("\(score)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(trending ? .green : .red)
                Image(systemName: trending ? "arrow.up" : "arrow.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(trending ? .green : .red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Profile View (placeholder)
// ─────────────────────────────────────────────────────────────────────────────

struct PCProfileView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        // Avatar with glass
                        Text("JD")
                            .font(.title2.bold())
                            .foregroundStyle(.green)
                            .frame(width: 60, height: 60)
                            .glassEffect(.regular.tint(.green.opacity(0.2)), in: .circle)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("John Doe")
                                .font(.headline)
                            Text("Level 6 · 2,340 / 5,000 XP")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Settings") {
                    Label("Personal Info",  systemImage: "person.text.rectangle")
                    Label("Goals",          systemImage: "target")
                    Label("Reminders",      systemImage: "bell")
                    Label("Apple Watch",    systemImage: "applewatch")
                    Label("Notifications",  systemImage: "app.badge")
                }

                Section("Support") {
                    Label("Help & Support", systemImage: "questionmark.circle")
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

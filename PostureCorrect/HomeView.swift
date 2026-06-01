//
//  HomeView.swift
//  PostureCorrect
//

import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(white: 0.07), Color.black],
                               startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 6) {
                        Text("💪 Posture AI")
                            .font(.largeTitle.bold()).foregroundColor(.white)
                        Text("Real-time form coaching")
                            .font(.subheadline).foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.top, 60).padding(.bottom, 40)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {

                            // ── Strength ──────────────────────────────────────
                            sectionHeader("Strength")
                            NavigationLink(destination: PushupCameraView()) {
                                ExerciseCard(icon: "figure.strengthtraining.traditional",
                                             title: "Push-ups",
                                             subtitle: "Rep counter · elbow, hip & back",
                                             color: .blue, tip: "Side-on camera")
                            }
                            NavigationLink(destination: SquatCameraView()) {
                                ExerciseCard(icon: "figure.strengthtraining.traditional",
                                             title: "Squats",
                                             subtitle: "Rep counter · knee, hip & back",
                                             color: .yellow, tip: "Side-on camera")
                            }

                            // ── Core ──────────────────────────────────────────
                            sectionHeader("Core")
                            NavigationLink(destination: PlankCameraView()) {
                                ExerciseCard(icon: "figure.core.training",
                                             title: "Plank",
                                             subtitle: "Hold timer · hip, back & neck",
                                             color: .green, tip: "Side-on camera")
                            }
                            NavigationLink(destination: SidePlankCameraView()) {
                                ExerciseCard(icon: "figure.pilates",
                                             title: "Side Plank",
                                             subtitle: "Hold timer · body line, torso, arm & neck",
                                             color: .purple, tip: "Side-on camera")
                            }
                            NavigationLink(destination: DeadBugCameraView()) {
                                ExerciseCard(icon: "figure.roll",
                                             title: "Dead Bug",
                                             subtitle: "Rep counter · back, arm, leg & knee",
                                             color: .red, tip: "Side-on camera")
                            }
                            NavigationLink(destination: BirdDogCameraView()) {
                                ExerciseCard(icon: "figure.cooldown",
                                             title: "Bird-Dog",
                                             subtitle: "Rep counter · back, arm, leg & hip",
                                             color: .teal, tip: "Side-on camera")
                            }
                            NavigationLink(destination: MountainClimberCameraView()) {
                                ExerciseCard(icon: "figure.hiking",
                                             title: "Mountain Climber",
                                             subtitle: "Rep counter · plank back & knee drive",
                                             color: .mint, tip: "Side-on camera")
                            }

                            // ── Lower Body ────────────────────────────────────
                            sectionHeader("Lower Body")
                            NavigationLink(destination: LungeCameraView()) {
                                ExerciseCard(icon: "figure.walk",
                                             title: "Lunges",
                                             subtitle: "Rep counter · front knee, back knee & torso",
                                             color: .orange, tip: "Face camera front-on")
                            }
                            NavigationLink(destination: GluteBridgeCameraView()) {
                                ExerciseCard(icon: "figure.gymnastics",
                                             title: "Glute Bridge",
                                             subtitle: "Rep counter · hip extension, knee & back",
                                             color: .pink, tip: "Side-on camera")
                            }

                            // ── Cardio ────────────────────────────────────────
                            sectionHeader("Cardio")
                            NavigationLink(destination: BurpeeCameraView()) {
                                ExerciseCard(icon: "figure.jumprope",
                                             title: "Burpee",
                                             subtitle: "Rep counter · plank, jump & back",
                                             color: .indigo, tip: "Side-on camera")
                            }
                            NavigationLink(destination: JumpingJackCameraView()) {
                                ExerciseCard(icon: "figure.mixed.cardio",
                                             title: "Jumping Jack",
                                             subtitle: "Rep counter · arm raise, leg spread & symmetry",
                                             color: .cyan, tip: "Face camera front-on")
                            }
                        }
                        .padding(.horizontal, 20).padding(.bottom, 30)
                    }

                    Text("Place your phone so your full body is visible")
                        .font(.caption).foregroundColor(.white.opacity(0.3))
                        .multilineTextAlignment(.center).padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.bold()).foregroundColor(.white.opacity(0.4))
                .textCase(.uppercase).tracking(1.5)
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
        }
        .padding(.top, 8)
    }
}

struct ExerciseCard: View {
    let icon: String; let title: String; let subtitle: String
    let color: Color; let tip: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 30)).foregroundColor(color)
                .frame(width: 60, height: 60)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.bold()).foregroundColor(.white)
                Text(subtitle).font(.caption).foregroundColor(.white.opacity(0.55))
                HStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 9)).foregroundColor(color.opacity(0.8))
                    Text(tip).font(.system(size: 11)).foregroundColor(color.opacity(0.8))
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(color.opacity(0.25), lineWidth: 1))
    }
}

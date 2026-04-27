import SwiftUI

struct WelcomeView: View {
    @State private var showSignUp = false
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 22) {
                    WelcomeHeroArt()
                        .frame(width: 260, height: 250)
                    Text("Chores")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("Keep your home in order,\ntogether.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                VStack(spacing: 12) {
                    Button("Create an account") { showSignUp = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)

                    Button("Sign in") { showLogin = true }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
            .navigationDestination(isPresented: $showSignUp) { SignUpView() }
            .navigationDestination(isPresented: $showLogin) { LoginView() }
        }
    }
}

private struct WelcomeHeroArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.blue.opacity(0.14))
                .frame(width: 190, height: 220)
                .rotationEffect(.degrees(-8))
                .offset(x: -18, y: 8)
            RoundedRectangle(cornerRadius: 8)
                .fill(.orange.opacity(0.16))
                .frame(width: 170, height: 205)
                .rotationEffect(.degrees(9))
                .offset(x: 24, y: 14)

            VStack(spacing: 12) {
                HStack {
                    Label("Today", systemImage: "sun.max.fill")
                        .font(.headline.weight(.bold))
                    Spacer()
                    Label("12", systemImage: "flame.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                HeroChorePill(title: "Dishes", tint: .red, icon: "exclamationmark.circle.fill")
                HeroChorePill(title: "Trash", tint: .orange, icon: "clock.fill")
                HeroChorePill(title: "Wipe counters", tint: .gray, icon: "bolt.fill")

                HStack(spacing: 8) {
                    HeroMiniCard(icon: "square.grid.2x2.fill", title: "Rooms", tint: .blue)
                    HeroMiniCard(icon: "gift.fill", title: "Rewards", tint: .pink)
                }
            }
            .padding(16)
            .frame(width: 220)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 18, y: 10)
        }
    }
}

private struct HeroChorePill: View {
    let title: String
    let tint: Color
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct HeroMiniCard: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview { WelcomeView() }

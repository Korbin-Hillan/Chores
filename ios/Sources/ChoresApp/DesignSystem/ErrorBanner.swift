import SwiftUI
import UIKit

struct ErrorBanner: ViewModifier {
    @Binding var error: APIError?

    func body(content: Content) -> some View {
        content
            .alert("Something went wrong", isPresented: .init(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: {
                if let error {
                    Text(error.localizedDescription)
                }
            }
    }
}

extension View {
    func errorAlert(_ error: Binding<APIError?>) -> some View {
        modifier(ErrorBanner(error: error))
    }
}

struct LoadingOverlay: ViewModifier {
    let isLoading: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if isLoading {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.5)
                }
            }
        }
    }
}

extension View {
    func loadingOverlay(_ isLoading: Bool) -> some View {
        modifier(LoadingOverlay(isLoading: isLoading))
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var action: (() -> Void)?
    var actionTitle: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let action, let title = actionTitle {
                Button(title, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct UserAvatarView: View {
    let userId: String
    let displayName: String
    let hasAvatar: Bool
    var size: CGFloat = 36

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Circle()
                .fill(avatarColor)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Text(initials)
                    .font(.system(size: max(11, size * 0.34), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.background, lineWidth: max(1, size * 0.06)))
        .task(id: "\(userId)-\(hasAvatar)") { await loadAvatarIfNeeded() }
    }

    private var initials: String {
        let parts = displayName
            .split(separator: " ")
            .map(String.init)
        let letters = parts.prefix(2).compactMap { $0.first }.map { String($0).uppercased() }
        if !letters.isEmpty { return letters.joined() }
        return String(displayName.prefix(2)).uppercased()
    }

    private var avatarColor: Color {
        let palette: [Color] = [
            .blue, .green, .orange, .pink, .purple, .teal, .indigo, .red, .cyan, .mint,
        ]
        let index = abs(stableHash(userId)) % palette.count
        return palette[index]
    }

    private func stableHash(_ value: String) -> Int {
        value.unicodeScalars.reduce(5381) { (($0 << 5) &+ $0) &+ Int($1.value) }
    }

    private func loadAvatarIfNeeded() async {
        guard hasAvatar else {
            image = nil
            return
        }
        guard let data = try? await APIClient.shared.data(path: "/auth/users/\(userId)/avatar") else {
            image = nil
            return
        }
        image = UIImage(data: data)
    }
}

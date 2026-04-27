import SwiftUI
import PhotosUI
import UIKit

@Observable
@MainActor
final class ChoreCompletionHistoryViewModel {
    private(set) var items: [ChoreCompletionHistoryItem] = []
    private(set) var isLoading = false
    var error: APIError?

    func load(householdId: String, choreId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await APIClient.shared.send(
                path: "/households/\(householdId)/chores/\(choreId)/completions",
                query: [URLQueryItem(name: "limit", value: "20")]
            )
        } catch let err as APIError {
            error = err
        } catch {
            self.error = .server(code: "INTERNAL", message: error.localizedDescription)
        }
    }
}

struct ChoreDetailView: View {
    let chore: APIChore
    let viewModel: ChoresViewModel
    let householdId: String

    @State private var showComplete = false
    @State private var historyViewModel = ChoreCompletionHistoryViewModel()

    private var schedule: ChoreScheduleSnapshot {
        chore.scheduleSnapshot()
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Title", value: chore.title)
                if let desc = chore.description, !desc.isEmpty {
                    LabeledContent("Notes", value: desc)
                }
            }
            Section("Schedule") {
                LabeledContent("Repeats", value: chore.recurrence.kind.rawValue.capitalized)
                if let statusText {
                    LabeledContent("Status", value: statusText)
                }
                if let nextDueText {
                    LabeledContent("Next due", value: nextDueText)
                }
                if let lastCompletedText {
                    LabeledContent("Last done", value: lastCompletedText)
                }
                if let mins = chore.estimatedMinutes {
                    LabeledContent("Estimated", value: "\(mins) min")
                }
                LabeledContent("Points", value: "\(chore.points)")
            }
            Section("Info") {
                LabeledContent("Source", value: chore.source == "manual" ? "Created manually" : "AI generated")
            }
            Section {
                Button("Mark as complete") { showComplete = true }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.green)
            }

            Section("Completion history") {
                if historyViewModel.isLoading && historyViewModel.items.isEmpty {
                    ProgressView()
                } else if historyViewModel.items.isEmpty {
                    Text("No completions yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(historyViewModel.items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.completedBy.displayName)
                                .font(.subheadline.weight(.medium))
                            Text(historyTimestamp(for: item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let notes = item.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if item.reviewStatus == "pending" {
                                Label("Pending review", systemImage: "hourglass")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            if item.hasPhoto {
                                CompletionPhotoView(householdId: householdId, completionId: item.id)
                                    .frame(width: 84, height: 84)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle(chore.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showComplete, onDismiss: {
            Task { await historyViewModel.load(householdId: householdId, choreId: chore.id) }
        }) {
            CompleteChoreSheet(chore: chore, householdId: householdId, viewModel: viewModel)
        }
        .errorAlert($historyViewModel.error)
        .task(id: chore.id) { await historyViewModel.load(householdId: householdId, choreId: chore.id) }
    }

    private var statusText: String? {
        switch schedule.state {
        case .unscheduled:
            return "No recurrence"
        case .dueToday:
            return "Due today"
        case .overdue(let date):
            return "Overdue since \(formatDate(date, includeTime: false))"
        case .upcoming(let date):
            return "Upcoming on \(formatDate(date, includeTime: false))"
        }
    }

    private var nextDueText: String? {
        guard let nextDueDate = schedule.nextDueDate else { return nil }
        return formatDate(nextDueDate, includeTime: false)
    }

    private var lastCompletedText: String? {
        guard let lastCompletedDate = schedule.lastCompletedDate else { return nil }
        return formatDate(lastCompletedDate, includeTime: true)
    }

    private func historyTimestamp(for item: ChoreCompletionHistoryItem) -> String {
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: item.completedAt) ?? .now
        return formatDate(date, includeTime: true)
    }

    private func formatDate(_ date: Date, includeTime: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = includeTime ? .short : .none
        return formatter.string(from: date)
    }
}

struct CompletionPhotoView: View {
    let householdId: String
    let completionId: String

    @State private var image: UIImage?
    @State private var showFullScreenPhoto = false

    var body: some View {
        Button {
            if image != nil {
                showFullScreenPhoto = true
            }
        } label: {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .buttonStyle(.plain)
        .task(id: completionId) { await load() }
        .fullScreenCover(isPresented: $showFullScreenPhoto) {
            if let image {
                FullScreenPhotoView(image: image)
            }
        }
    }

    private func load() async {
        guard let data = try? await APIClient.shared.data(
            path: "/households/\(householdId)/completions/\(completionId)/photo"
        ) else { return }
        image = UIImage(data: data)
    }
}

private struct FullScreenPhotoView: View {
    let image: UIImage

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZoomableImage(image: image)
                .background(Color.black)
                .ignoresSafeArea(edges: .bottom)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
                .toolbarBackground(.black, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.backgroundColor = .black

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
        _ = scrollView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }
    }
}

struct CompleteChoreSheet: View {
    let chore: APIChore
    let householdId: String
    let viewModel: ChoresViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var notes = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var showCamera = false
    @State private var isCompleting = false
    @State private var milestoneStreak: Int?

    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                    Section("Completion") {
                        TextField("Notes (optional)", text: $notes, axis: .vertical)
                            .lineLimit(2...4)
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button {
                                showCamera = true
                            } label: {
                                Label("Camera", systemImage: "camera")
                            }
                        }
                        PhotosPicker(
                            selection: $selectedPhoto,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Label(photoData == nil ? "Choose from library" : "Change library photo", systemImage: "photo")
                        }
                        if let photoData, let image = UIImage(data: photoData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        if chore.requiresPhotoEvidence {
                            Label("Photo required", systemImage: "checkmark.seal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if chore.requiresParentApproval {
                            Label("Completion will be pending parent review", systemImage: "hourglass")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let milestoneStreak {
                    CompletionMilestoneView(streak: milestoneStreak)
                        .transition(.opacity.combined(with: .scale))
                        .zIndex(2)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                dismiss()
                            }
                        }
                }
            }
            .navigationTitle(chore.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Complete") { complete() }
                        .disabled(isCompleting || (chore.requiresPhotoEvidence && photoData == nil))
                }
            }
            .loadingOverlay(isCompleting)
            .onChange(of: selectedPhoto) { _, newValue in
                Task { await loadPhoto(newValue) }
            }
            .sheet(isPresented: $showCamera) {
                CameraCaptureView { image in
                    photoData = downscaledJPEG(from: image)
                }
            }
        }
    }

    private func complete() {
        isCompleting = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            defer { isCompleting = false }
            let response = await viewModel.completeChore(
                chore.id,
                householdId: householdId,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
                photoData: photoData,
                photoContentType: photoData == nil ? nil : "image/jpeg"
            )
            if let streak = response?.membership.currentStreak, [7, 30, 100].contains(streak) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    milestoneStreak = streak
                }
            } else {
                dismiss()
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        photoData = downscaledJPEG(from: data)
    }

    private func downscaledJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return compressedEvidenceJPEG(from: image)
    }

    private func downscaledJPEG(from image: UIImage) -> Data? {
        compressedEvidenceJPEG(from: image)
    }

    private func compressedEvidenceJPEG(from image: UIImage) -> Data? {
        let targetBytes = 280_000
        let maxSides: [CGFloat] = [800, 700, 600, 500, 400]
        let qualities: [CGFloat] = [0.7, 0.6, 0.5, 0.42, 0.35]

        var smallestData: Data?
        for maxSide in maxSides {
            let resized = resizedImage(image, maxSide: maxSide)
            for quality in qualities {
                guard let data = resized.jpegData(compressionQuality: quality) else { continue }
                if data.count <= targetBytes {
                    return data
                }
                if smallestData == nil || data.count < (smallestData?.count ?? Int.max) {
                    smallestData = data
                }
            }
        }
        return smallestData
    }

    private func resizedImage(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

private struct CompletionMilestoneView: View {
    let streak: Int

    var body: some View {
        VStack(spacing: 10) {
            Label("\(streak) day streak", systemImage: "flame.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(.orange)
            Text("Milestone reached")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 18)
        .padding()
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        _ = uiViewController
        _ = context
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        let dismiss: DismissAction

        init(onImage: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

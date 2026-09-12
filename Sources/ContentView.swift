import Photos
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = PhotoLibraryViewModel()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.12, blue: 0.14),
                    Color(red: 0.035, green: 0.04, blue: 0.055)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                .ignoresSafeArea()

            switch model.authorizationStatus {
            case .notDetermined:
                LoadingView(message: "Checking your photo library…")
            case .denied, .restricted:
                PermissionView(isLimited: false)
            case .authorized:
                if model.isLoading && model.assets.isEmpty {
                    LoadingView(message: "Loading your photos…")
                } else if model.assets.isEmpty {
                    EmptyLibraryView()
                } else {
                    ReviewView(model: model)
                }
            case .limited:
                if model.isLoading && model.assets.isEmpty {
                    LoadingView(message: "Loading your selected photos…")
                } else if model.assets.isEmpty {
                    PermissionView(isLimited: true)
                } else {
                    ReviewView(model: model)
                }
            @unknown default:
                PermissionView(isLimited: false)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            model.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refreshAuthorization()
            }
        }
        .alert(
            "Photo library error",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        model.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Something went wrong.")
        }
    }

    @ViewBuilder
    private func PermissionView(isLimited: Bool) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.mint)

            Text(isLimited ? "Choose more photos" : "Photo access is off")
                .font(.title2.bold())

            Text(
                isLimited
                    ? "Photo Cleanz can only review the photos you selected. Update access to clean more."
                    : "Photo Cleanz needs Photos access to show your library and apply the deletes you confirm."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 360)

            Button("Open Photos Settings") {
                openSettings()
            }
            .buttonStyle(.borderedProminent)
            .tint(.mint)
        }
        .padding(32)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct LoadingView: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.mint)
                .scaleEffect(1.2)
            Text(message)
                .foregroundStyle(.secondary)
        }
    }
}

private struct EmptyLibraryView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.stack")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.mint)
            Text("No photos to review")
                .font(.title2.bold())
            Text("Your selected Photos library is empty.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct ReviewView: View {
    @ObservedObject var model: PhotoLibraryViewModel

    var body: some View {
        reviewStack
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.white.opacity(0.045))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .overlay {
            loadingOverlay
        }
    }

    private var reviewStack: some View {
        VStack(spacing: 16) {
            header
            reviewContent
            controls
        }
    }

    @ViewBuilder
    private var reviewContent: some View {
        if let asset = model.currentAsset {
            photoCard(for: asset)
        } else {
            finishedView
        }
    }

    private func photoCard(for asset: PHAsset) -> some View {
        PhotoAssetImage(asset: asset)
            .frame(maxWidth: 900, minHeight: 300, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
            .layoutPriority(1)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                photoBadge
            }
            .contentShape(Rectangle())
            .gesture(swipeGesture)
            .accessibilityLabel("Photo to review")
    }

    private var photoBadge: some View {
        Text("PHOTO \(model.currentIndex + 1)")
            .font(.caption.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.black.opacity(0.48), in: Capsule())
            .padding(14)
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if model.isLoading {
            ZStack {
                Color.black.opacity(0.38)
                ProgressView()
                    .tint(.mint)
                    .scaleEffect(1.2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Photo Cleanz")
                        .font(.title2.weight(.bold))
                    Text(model.currentAsset == nil ? "Review complete" : "Keep the good stuff")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if model.pendingDeleteCount > 0 {
                    Button {
                        model.requestDelete()
                    } label: {
                        Label("Delete \(model.pendingDeleteCount)", systemImage: "trash.fill")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.regular)
                }
            }

            HStack {
                ProgressView(
                    value: Double(model.currentIndex),
                    total: Double(max(model.assets.count, 1))
                )
                .tint(.mint)

                Text("\(model.currentIndex)/\(model.assets.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("\(model.remainingCount) left", systemImage: "square.stack.3d.up")
                Spacer()
                Label("\(model.pendingDeleteCount) marked", systemImage: "trash")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if model.currentAsset != nil {
                Text("Swipe left/right or tap a choice")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    decisionButton(
                        title: "Delete",
                        systemImage: "trash",
                        tint: .red,
                        action: model.markCurrentForDeletion
                    )

                    decisionButton(
                        title: "Keep",
                        systemImage: "heart.fill",
                        tint: .mint,
                        action: model.keepCurrent
                    )
                }

                Button {
                    model.undoLastDecision()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(model.currentIndex > 0 ? 1 : 0.35)
                .disabled(model.currentIndex == 0)
            } else {
                Button("Start over", action: model.startOver)
                    .buttonStyle(.bordered)
                    .tint(.mint)
            }
        }
        .alert(
            "Delete \(model.pendingDeleteCount) photos?",
            isPresented: $model.showDeleteConfirmation
        ) {
            Button("Delete", role: .destructive, action: model.deleteMarkedPhotos)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They will move to Recently Deleted in Photos. This only removes photos you marked.")
        }
    }

    private func decisionButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .controlSize(.large)
    }

    private var finishedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.mint)
            Text("All caught up")
                .font(.title.bold())
            Text(
                model.pendingDeleteCount == 0
                    ? "You kept every photo in this round."
                    : "Your marked photos are waiting for confirmation."
            )
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 900, maxHeight: .infinity)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                if value.translation.width < -90 {
                    model.markCurrentForDeletion()
                } else if value.translation.width > 90 {
                    model.keepCurrent()
                }
            }
    }
}

#Preview {
    ContentView()
}

import Combine
import Foundation
import Photos

final class PhotoLibraryViewModel: NSObject, ObservableObject {
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var pendingDeleteIDs: Set<String> = []
    @Published private(set) var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var showDeleteConfirmation = false

    private struct Decision {
        let identifier: String
        let wasMarkedForDeletion: Bool
    }

    private var decisionHistory: [Decision] = []
    private var didStart = false
    private var loadGeneration = 0

    var currentAsset: PHAsset? {
        guard assets.indices.contains(currentIndex) else { return nil }
        return assets[currentIndex]
    }

    var remainingCount: Int {
        max(assets.count - currentIndex, 0)
    }

    var pendingDeleteCount: Int {
        pendingDeleteIDs.count
    }

    var hasFinishedReview: Bool {
        !assets.isEmpty && currentIndex >= assets.count
    }

    var canReadPhotos: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    override init() {
        super.init()
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        refreshAuthorization(requestIfNeeded: true)
    }

    func refreshAuthorization(requestIfNeeded: Bool = false) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorizationStatus = status

        switch status {
        case .authorized, .limited:
            if assets.isEmpty || !didStart {
                loadAssets()
            }
        case .notDetermined where requestIfNeeded:
            requestAuthorization()
        default:
            break
        }
    }

    private func requestAuthorization() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                self.authorizationStatus = status
                if self.canReadPhotos {
                    self.loadAssets()
                }
            }
        }
    }

    func loadAssets() {
        guard canReadPhotos else { return }

        isLoading = true
        errorMessage = nil
        loadGeneration += 1
        let generation = loadGeneration

        DispatchQueue.global(qos: .userInitiated).async {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

            let result = PHAsset.fetchAssets(with: .image, options: options)
            var fetchedAssets: [PHAsset] = []
            fetchedAssets.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in
                fetchedAssets.append(asset)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.loadGeneration else { return }
                self.assets = fetchedAssets.shuffled()
                self.currentIndex = 0
                self.pendingDeleteIDs.removeAll()
                self.decisionHistory.removeAll()
                self.isLoading = false
            }
        }
    }

    func keepCurrent() {
        decide(markForDeletion: false)
    }

    func markCurrentForDeletion() {
        decide(markForDeletion: true)
    }

    private func decide(markForDeletion: Bool) {
        guard let asset = currentAsset else { return }

        let identifier = asset.localIdentifier
        decisionHistory.append(
            Decision(
                identifier: identifier,
                wasMarkedForDeletion: pendingDeleteIDs.contains(identifier)
            )
        )

        if markForDeletion {
            pendingDeleteIDs.insert(identifier)
        } else {
            pendingDeleteIDs.remove(identifier)
        }

        currentIndex += 1
    }

    func undoLastDecision() {
        guard currentIndex > 0, let previous = decisionHistory.popLast() else { return }

        currentIndex -= 1
        if previous.wasMarkedForDeletion {
            pendingDeleteIDs.insert(previous.identifier)
        } else {
            pendingDeleteIDs.remove(previous.identifier)
        }
    }

    func startOver() {
        guard !assets.isEmpty else {
            loadAssets()
            return
        }

        assets = assets.shuffled()
        currentIndex = 0
        pendingDeleteIDs.removeAll()
        decisionHistory.removeAll()
    }

    func requestDelete() {
        guard pendingDeleteCount > 0 else { return }
        showDeleteConfirmation = true
    }

    func deleteMarkedPhotos() {
        let selectedAssets = assets.filter { pendingDeleteIDs.contains($0.localIdentifier) }
        guard !selectedAssets.isEmpty else { return }

        showDeleteConfirmation = false
        isLoading = true

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(selectedAssets as NSArray)
        }) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false

                if success {
                    self.pendingDeleteIDs.removeAll()
                    self.decisionHistory.removeAll()
                    self.errorMessage = nil
                    self.loadAssets()
                } else {
                    self.errorMessage = error?.localizedDescription ?? "Photos could not be deleted."
                }
            }
        }
    }
}

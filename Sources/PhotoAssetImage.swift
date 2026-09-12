import Combine
import Photos
import SwiftUI
import UIKit

final class PhotoAssetImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?

    private let imageManager = PHImageManager.default()
    private var requestID: PHImageRequestID = PHInvalidImageRequestID
    private var loadToken = UUID()

    deinit {
        cancel()
    }

    func load(asset: PHAsset) {
        cancel()
        image = nil
        let token = UUID()
        loadToken = token

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        requestID = imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 1600, height: 1600),
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, _ in
            guard let image else { return }
            DispatchQueue.main.async {
                guard let self, self.loadToken == token else { return }
                self.image = image
            }
        }
    }

    func cancel() {
        guard requestID != PHInvalidImageRequestID else { return }
        imageManager.cancelImageRequest(requestID)
        requestID = PHInvalidImageRequestID
    }
}

struct PhotoAssetImage: View {
    let asset: PHAsset

    @StateObject private var loader = PhotoAssetImageLoader()

    var body: some View {
        ZStack {
            Color.black

            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .onAppear {
            loader.load(asset: asset)
        }
        .onChange(of: asset.localIdentifier) { _, _ in
            loader.load(asset: asset)
        }
        .onDisappear {
            loader.cancel()
        }
    }
}

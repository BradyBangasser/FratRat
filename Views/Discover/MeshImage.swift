//
//  MeshImage.swift
//  FratRat
//

import SwiftUI
import Combine

// MARK: - MeshImage

struct MeshImage: View {
    var blobId:        String?
    var blobKey:       Data?    // ChaCha20 symmetric key — required to decrypt peer photos
    var localFilename: String?
    var initials:      String   = "?"
    var size:          CGFloat  = 54
    var cornerRadius:  CGFloat? = nil
    var contentMode:   ContentMode = .fill

    @EnvironmentObject private var mesh: MeshManager
    @StateObject private var loader = ImageLoader()

    private var radius: CGFloat { cornerRadius ?? size / 4 }

    var body: some View {
        ZStack {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                InitialsAvatar(initials: initials, size: size)
            }

            if loader.isLoading {
                ZStack {
                    Color.black.opacity(0.3)
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: blobId ?? localFilename ?? "") {
            await loader.load(
                blobId:        blobId,
                blobKey:       blobKey,
                localFilename: localFilename,
                mesh:          mesh
            )
        }
    }
}

// MARK: - Circle convenience

extension MeshImage {
    static func circle(
        blobId:        String?  = nil,
        blobKey:       Data?    = nil,
        localFilename: String?  = nil,
        initials:      String   = "?",
        size:          CGFloat  = 54
    ) -> MeshImage {
        MeshImage(
            blobId:        blobId,
            blobKey:       blobKey,
            localFilename: localFilename,
            initials:      initials,
            size:          size,
            cornerRadius:  size / 2
        )
    }
}

// MARK: - ImageLoader

@MainActor
class ImageLoader: ObservableObject {
    @Published var image:      UIImage? = nil
    @Published var isLoading           = false

    private static var cache: [String: UIImage] = [:]

    func load(
        blobId:        String?,
        blobKey:       Data?,
        localFilename: String?,
        mesh:          MeshManager
    ) async {
        image = nil

        // 1. Local file — own photos, shown instantly from disk
        if let filename = localFilename, !filename.isEmpty {
            if let img = ImageStore.load(filename) {
                image = img
                return
            }
        }

        // 2. Remote blob — requires both the CF URL and its decryption key
        if let id = blobId, !id.isEmpty, let key = blobKey {
            if let cached = Self.cache[id] {
                image = cached
                return
            }

            isLoading = true
            defer { isLoading = false }

            do {
                let data = try await mesh.retrievePhoto(url: id, key: key)
                if let img = UIImage(data: data) {
                    Self.cache[id] = img
                    image = img
                }
            } catch {
                // Blob not available — initials fallback stays visible
            }
        }
    }

    static func clearCache() {
        cache.removeAll()
    }
}

// MARK: - InitialsAvatar

struct InitialsAvatar: View {
    let initials:     String
    let size:         CGFloat
    var cornerRadius: CGFloat? = nil
    var colors:       [Color]  = [.fratPink, Color(red: 0.8, green: 0.2, blue: 0.5)]

    private var radius: CGFloat { cornerRadius ?? size / 2 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initials.prefix(2).uppercased())
                .font(.system(size: size * 0.35, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    VStack(spacing: 20) {
        MeshImage.circle(initials: "BJ", size: 54)
        MeshImage(initials: "AB", size: 120, cornerRadius: 16)
        InitialsAvatar(initials: "CD", size: 44)
    }
    .padding()
    .environmentObject(MeshManager())
}

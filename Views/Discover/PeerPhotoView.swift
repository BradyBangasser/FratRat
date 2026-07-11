//
//  PeerPhotoView.swift
//  FratRat
//

import SwiftUI

// MARK: - PeerPhotoView

struct PeerPhotoView: View {
    let photoBlobIds:  [String]
    let photoBlobKeys: [Data]
    let initials:      String
    var height:        CGFloat = 480

    @EnvironmentObject var mesh: MeshManager
    @State private var currentIndex = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            // Photo
            MeshImage(
                blobId:  photoBlobIds.indices.contains(currentIndex)
                             ? photoBlobIds[currentIndex] : nil,
                blobKey: photoBlobKeys.indices.contains(currentIndex)
                             ? photoBlobKeys[currentIndex] : nil,
                initials:    initials,
                size:        height,
                cornerRadius: 24,
                contentMode: .fill
            )
            .frame(maxWidth: .infinity, maxHeight: height)
            .clipped()

            // Multi-photo navigation + dots
            if photoBlobIds.count > 1 {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if currentIndex > 0 { currentIndex -= 1 }
                            }
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if currentIndex < photoBlobIds.count - 1 { currentIndex += 1 }
                            }
                    }

                    HStack(spacing: 5) {
                        ForEach(photoBlobIds.indices, id: \.self) { i in
                            Capsule()
                                .fill(i == currentIndex ? Color.white : Color.white.opacity(0.5))
                                .frame(width: i == currentIndex ? 16 : 6, height: 6)
                                .animation(.easeInOut(duration: 0.2), value: currentIndex)
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - OwnPhotoStrip
// Shows the current user's own photos from local disk (no key needed).

struct OwnPhotoStrip: View {
    let localFilenames: [String]
    let size:           CGFloat

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(localFilenames, id: \.self) { filename in
                    MeshImage(
                        localFilename: filename,
                        initials:      "",
                        size:          size,
                        cornerRadius:  12,
                        contentMode:   .fill
                    )
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

#Preview {
    PeerPhotoView(
        photoBlobIds:  [],
        photoBlobKeys: [],
        initials:      "AB"
    )
    .frame(height: 480)
    .padding()
    .environmentObject(MeshManager())
}

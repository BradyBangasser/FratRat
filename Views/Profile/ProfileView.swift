//
//  ProfileView.swift
//  FratRat
//

import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject var mesh: MeshManager
    @State private var profile      = UserProfile.load()
    @State private var photos:      [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var uploadProgress: (current: Int, total: Int)? = nil
    @State private var uploadFailed = false
    @State private var showSaved    = false
    @State private var isSaving     = false

    var body: some View {
        ZStack {
            Color.fratBg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Header ────────────────────────────────────────────────
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Profile")
                                .font(.system(size: 34, weight: .black))
                                .foregroundColor(.fratDark)
                            Text("Show off your vibe.")
                                .font(.fratBody(15))
                                .foregroundColor(.fratGray)
                        }
                        Spacer()
                        if showSaved {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .font(.fratSemi(13))
                                .foregroundColor(.green)
                                .transition(.opacity.combined(with: .scale))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 60)
                    .padding(.bottom, 24)

                    // ── Photos ────────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PHOTOS")
                            .font(.fratSemi(11))
                            .foregroundColor(.fratGray)
                            .padding(.horizontal, 24)

                        ProfilePhotoGrid(
                            photos:      $photos,
                            pickerItems: $pickerItems,
                            onRemove:    removePhoto
                        )
                        .padding(.horizontal, 24)

                        Group {
                            if let p = uploadProgress {
                                HStack(spacing: 8) {
                                    ProgressView().scaleEffect(0.8)
                                    Text("Uploading photo \(p.current) of \(p.total)…")
                                        .font(.fratBody(12)).foregroundColor(.fratGray)
                                }
                            } else if uploadFailed {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 12)).foregroundColor(.orange)
                                    Text("Some photos couldn't upload. They'll retry on next connect.")
                                        .font(.fratBody(12)).foregroundColor(.fratGray)
                                }
                            } else {
                                Text("Add up to 6 photos. Photos are encrypted before uploading.")
                                    .font(.fratBody(12)).foregroundColor(.fratGray)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 24)

                    // ── Fields ────────────────────────────────────────────────
                    VStack(spacing: 20) {
                        ProfileField(label: "NAME",    placeholder: "Your name",    value: $profile.name)
                        ProfileField(label: "COLLEGE", placeholder: "Your college", value: $profile.college)
                        ProfileField(label: "YEAR",    placeholder: "Freshman / Sophomore / Junior / Senior", value: $profile.year)
                        ProfileField(label: "BIO",     placeholder: "Tell people about yourself…",
                                     value: $profile.bio, multiline: true)
                    }
                    .padding(.horizontal, 24)

                    // ── Peer ID ───────────────────────────────────────────────
                    if let peerId = mesh.myPeerId {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("MESH IDENTITY")
                                .font(.fratSemi(11)).foregroundColor(.fratGray)
                            HStack {
                                Text(peerId)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.fratGray).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Button { UIPasteboard.general.string = peerId } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 14)).foregroundColor(.fratPink)
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.fratCard))
                        }
                        .padding(.horizontal, 24).padding(.top, 8)
                    }

                    // ── Save button ───────────────────────────────────────────
                    Button {
                        Task { await saveProfile() }
                    } label: {
                        Group {
                            if isSaving {
                                HStack(spacing: 10) {
                                    ProgressView().tint(.white)
                                    Text("Saving…").font(.fratBold(17)).foregroundColor(.white)
                                }
                            } else {
                                Text("Save profile").font(.fratBold(17)).foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(isSaving ? Color.fratGray : Color.fratPink)
                        )
                    }
                    .disabled(isSaving)
                    .padding(.horizontal, 24).padding(.top, 32).padding(.bottom, 120)
                }
            }
        }
        .onAppear { loadExistingPhotos() }
        .onChange(of: pickerItems) { _, newItems in
            Task { await appendPickedPhotos(newItems) }
        }
    }

    // MARK: - Photo management

    private func loadExistingPhotos() {
        guard photos.isEmpty else { return }
        photos = profile.localPhotoFilenames.compactMap { ImageStore.load($0) }
    }

    // @MainActor so @State mutations are always on the main thread
    @MainActor
    private func appendPickedPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard photos.count < 6 else { break }
            if let data  = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                photos.append(image)
            }
        }
        pickerItems = []
    }

    @MainActor
    private func removePhoto(at index: Int) {
        guard photos.indices.contains(index) else { return }
        photos.remove(at: index)
        if profile.localPhotoFilenames.indices.contains(index) {
            ImageStore.delete(profile.localPhotoFilenames[index])
            profile.localPhotoFilenames.remove(at: index)
        }
        if profile.photoURLs.indices.contains(index) { profile.photoURLs.remove(at: index) }
        if profile.photoKeys.indices.contains(index)  { profile.photoKeys.remove(at: index) }
    }

    // MARK: - Save + upload
    // @MainActor ensures every mutation to @State (profile, isSaving, etc.)
    // happens on the main thread regardless of where await resumes.

    @MainActor
    private func saveProfile() async {
        guard !isSaving else { return }
        isSaving     = true
        uploadFailed = false

        // 1. Persist current photo images to disk
        for filename in profile.localPhotoFilenames { ImageStore.delete(filename) }
        profile.localPhotoFilenames = photos.compactMap { ImageStore.save($0) }

        // 2. Upload only photos that don't already have a CF URL
        let alreadyUploaded = min(profile.photoURLs.count, photos.count)
        var cfUrls = Array(profile.photoURLs.prefix(alreadyUploaded))
        var keys   = Array(profile.photoKeys.prefix(alreadyUploaded))

        let newFilenames = Array(profile.localPhotoFilenames.dropFirst(alreadyUploaded))
        if !newFilenames.isEmpty {
            uploadProgress = (current: 0, total: newFilenames.count)

            for (i, filename) in newFilenames.enumerated() {
                uploadProgress = (current: i + 1, total: newFilenames.count)
                guard let data = ImageStore.data(for: filename) else { continue }

                var uploaded = false
                for attempt in 1...3 {
                    do {
                        let result = try await mesh.uploadPhoto(data)
                        cfUrls.append(result.url)
                        keys.append(result.key)
                        uploaded = true
                        break
                    } catch {
                        Swift.print("[profile] upload attempt \(attempt) failed: \(error)")
                        if attempt < 3 {
                            try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
                        }
                    }
                }
                if !uploaded { Swift.print("[profile] gave up on \(filename)") }
            }
        }

        // 3. Commit to SQLite
        profile.photoURLs = cfUrls
        profile.photoKeys = keys
        profile.save()

        uploadProgress = nil
        uploadFailed   = cfUrls.count < profile.localPhotoFilenames.count
        isSaving       = false

        // 4. Announce on the mesh and update our own peerProfiles entry
        //    so any in-app view that reads mesh.peerProfiles[myPeerId] reflects
        //    the new photos immediately without waiting for a remote echo.
        await mesh.announceProfile()
        if let myId = mesh.myPeerId, let updated = loadUserProfile() {
            mesh.peerProfiles[myId] = updated
        }

        withAnimation { showSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSaved = false }
        }
    }
}

// MARK: - Photo grid

private struct ProfilePhotoGrid: View {
    @Binding var photos:      [UIImage]
    @Binding var pickerItems: [PhotosPickerItem]
    let onRemove: (Int) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: photo)
                        .resizable().scaledToFill()
                        .frame(height: 110).frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    if index == 0 {
                        Text("MAIN").font(.fratSemi(9)).foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Capsule().fill(Color.fratPink))
                            .padding(6)
                    }

                    Button { onRemove(index) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18)).foregroundColor(.white)
                            .shadow(color: .black.opacity(0.4), radius: 3)
                    }
                    .padding(6).padding(.top, index == 0 ? 22 : 0)
                }
            }

            if photos.count < 6 {
                PhotosPicker(
                    selection:         $pickerItems,
                    maxSelectionCount: 6 - photos.count,
                    matching:          .images
                ) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.fratCard)
                            .frame(height: 110)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(
                                        Color.fratGray.opacity(0.3),
                                        style: StrokeStyle(lineWidth: 1.5, dash: [5])
                                    )
                            )
                        VStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.fratGray)
                            Text("Add photo").font(.fratBody(11)).foregroundColor(.fratGray)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Profile field

private struct ProfileField: View {
    let label:       String
    let placeholder: String
    @Binding var value: String
    var multiline: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.fratSemi(11)).foregroundColor(.fratGray)

            if multiline {
                ZStack(alignment: .topLeading) {
                    if value.isEmpty {
                        Text(placeholder)
                            .font(.fratBody(15)).foregroundColor(.fratGray.opacity(0.6))
                            .padding(.horizontal, 14).padding(.top, 12)
                    }
                    TextEditor(text: $value)
                        .font(.fratBody(15)).foregroundColor(.fratDark)
                        .frame(minHeight: 90)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .scrollContentBackground(.hidden)
                        .onChange(of: value) { _, v in
                            if v.count > 200 { value = String(v.prefix(200)) }
                        }
                }
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.fratCard))
            } else {
                TextField(placeholder, text: $value)
                    .font(.fratBody(15)).foregroundColor(.fratDark)
                    .padding(.horizontal, 14).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.fratCard))
            }
        }
    }
}

#Preview { ProfileView().environmentObject(MeshManager()) }

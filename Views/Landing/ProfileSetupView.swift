//
//  ProfileSetupView.swift
//  FratRat
//

import SwiftUI
import PhotosUI

// MARK: - ProfileSetupView

struct ProfileSetupView: View {
    @EnvironmentObject var mesh: MeshManager
    @Environment(\.dismiss) private var dismiss

    @State private var profile            = UserProfile.load()
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var photos:           [UIImage] = []
    @FocusState private var focusedField: Field?

    @State private var uploadProgress: (current: Int, total: Int)? = nil
    @State private var uploadFailed = false

    var onOnboardingComplete: () -> Void = {}

    private enum Field { case name, college, bio }
    private let maxPhotos = 6

    var body: some View {
        ZStack {
            Color.fratBg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Header ────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Set up your profile")
                            .font(.system(size: 28, weight: .black))
                            .foregroundColor(.fratDark)
                        Text("This is what other students will see.")
                            .font(.fratBody(15))
                            .foregroundColor(.fratGray)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 24)

                    // ── Photos ────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PHOTOS")
                            .font(.fratSemi(11))
                            .foregroundColor(.fratGray)

                        PhotoGrid(
                            photos:      $photos,
                            pickerItems: $photoPickerItems,
                            maxPhotos:   maxPhotos,
                            onRemove:    removePhoto
                        )

                        if uploadFailed {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                                Text("Some photos failed to upload. They'll retry when you reconnect.")
                                    .font(.fratBody(12))
                                    .foregroundColor(.fratGray)
                            }
                        } else {
                            Text("Add up to \(maxPhotos) photos. The first photo is your main profile picture.")
                                .font(.fratBody(12))
                                .foregroundColor(.fratGray)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                    // ── Name ──────────────────────────────────────────────
                    FieldLabel("NAME")
                    FieldBox {
                        TextField("Your name", text: $profile.name)
                            .font(.fratBody(16))
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .name)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                    // ── College ───────────────────────────────────────────
                    FieldLabel("COLLEGE")
                    FieldBox {
                        TextField("Your school", text: $profile.college)
                            .font(.fratBody(16))
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .college)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                    // ── Year ──────────────────────────────────────────────
                    FieldLabel("YEAR")
                    YearPicker(selection: $profile.year)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)

                    // ── Bio ───────────────────────────────────────────────
                    FieldLabel("BIO")
                    FieldBox {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField(
                                "A little about you…",
                                text: $profile.bio,
                                axis: .vertical
                            )
                            .font(.fratBody(16))
                            .lineLimit(3...6)
                            .focused($focusedField, equals: .bio)
                            .onChange(of: profile.bio) { newValue in
                                if newValue.count > 200 {
                                    profile.bio = String(newValue.prefix(200))
                                }
                            }

                            HStack {
                                Spacer()
                                Text("\(profile.bio.count)/200")
                                    .font(.fratBody(11))
                                    .foregroundColor(.fratGray)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                    Color.clear.frame(height: 100)
                }
            }

            // ── Continue button ───────────────────────────────────────────
            VStack {
                Spacer()
                Button {
                    saveAndContinue()
                } label: {
                    ZStack {
                        if let p = uploadProgress {
                            HStack(spacing: 10) {
                                ProgressView().tint(.white)
                                Text("Uploading \(p.current) of \(p.total)…")
                                    .font(.fratBold(17))
                                    .foregroundColor(.white)
                            }
                        } else {
                            Text("Continue")
                                .font(.fratBold(17))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(profile.isComplete ? Color.fratPink : Color.fratGray)
                    )
                }
                .disabled(!profile.isComplete || uploadProgress != nil)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .padding(.top, 12)
                .background(
                    LinearGradient(
                        colors: [Color.fratBg.opacity(0), Color.fratBg],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 100)
                    .allowsHitTesting(false),
                    alignment: .top
                )
            }
        }
        .onAppear { loadExistingPhotos() }
        .onChange(of: photoPickerItems) { newItems in
            Task { await loadPickedPhotos(newItems) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
                    .foregroundColor(.fratPink)
            }
        }
    }

    // MARK: - Photo loading

    private func loadExistingPhotos() {
        guard photos.isEmpty else { return }
        photos = profile.localPhotoFilenames.compactMap { ImageStore.load($0) }
    }

    private func loadPickedPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard photos.count < maxPhotos else { break }
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run { photos.append(image) }
            }
        }
        await MainActor.run { photoPickerItems = [] }
    }

    private func removePhoto(at index: Int) {
        guard photos.indices.contains(index) else { return }
        photos.remove(at: index)
        if profile.localPhotoFilenames.indices.contains(index) {
            let filename = profile.localPhotoFilenames[index]
            ImageStore.delete(filename)
            profile.localPhotoFilenames.remove(at: index)
        }
        if profile.photoURLs.indices.contains(index) {
            profile.photoURLs.remove(at: index)
        }
        if profile.photoKeys.indices.contains(index) {
            profile.photoKeys.remove(at: index)
        }
    }

    // MARK: - Save + continue

    private func saveAndContinue() {
        focusedField  = nil
        uploadFailed  = false

        for filename in profile.localPhotoFilenames { ImageStore.delete(filename) }
        profile.localPhotoFilenames = photos.compactMap { ImageStore.save($0) }
        profile.save()

        guard !photos.isEmpty else { onOnboardingComplete(); return }

        Task { await uploadPhotos() }
    }

    private func uploadPhotos() async {
        let filenames = await MainActor.run { profile.localPhotoFilenames }
        var cfUrls:  [String] = []
        var keys:    [Data]   = []

        for (i, filename) in filenames.enumerated() {
            await MainActor.run {
                uploadProgress = (current: i + 1, total: filenames.count)
            }

            guard let data = ImageStore.data(for: filename) else { continue }

            do {
                let result = try await mesh.uploadPhoto(data)
                cfUrls.append(result.url)
                keys.append(result.key)
            } catch {
                Swift.print("[blob] upload failed for \(filename): \(error)")
            }
        }

        await MainActor.run {
            uploadFailed       = cfUrls.count < filenames.count
            profile.photoURLs  = cfUrls
            profile.photoKeys  = keys
            profile.save()
            uploadProgress     = nil
            // Proceed even on partial failure — MeshManager.retryPendingPhotoUploads
            // will pick up the remaining photos on next relay connection.
            onOnboardingComplete()
        }
    }
}

// MARK: - Photo grid

private struct PhotoGrid: View {
    @Binding var photos:      [UIImage]
    @Binding var pickerItems: [PhotosPickerItem]
    let maxPhotos: Int
    let onRemove:  (Int) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(photos.indices, id: \.self) { index in
                PhotoTile(image: photos[index], isPrimary: index == 0) {
                    onRemove(index)
                }
            }

            if photos.count < maxPhotos {
                PhotosPicker(
                    selection:         $pickerItems,
                    maxSelectionCount: maxPhotos - photos.count,
                    matching:          .images
                ) {
                    AddPhotoTile()
                }
            }
        }
    }
}

// MARK: - Photo tile

private struct PhotoTile: View {
    let image:     UIImage
    let isPrimary: Bool
    let onRemove:  () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 110)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            if isPrimary {
                Text("MAIN")
                    .font(.fratSemi(9))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(Color.fratPink))
                    .padding(6)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.4), radius: 3)
            }
            .padding(6)
            .padding(.top, isPrimary ? 22 : 0)
        }
    }
}

// MARK: - Add photo tile

private struct AddPhotoTile: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.fratCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            Color.fratGray.opacity(0.3),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5])
                        )
                )
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.fratPink)
                Text("Add")
                    .font(.fratSemi(11))
                    .foregroundColor(.fratGray)
            }
        }
        .frame(height: 110)
    }
}

// MARK: - Field label

private struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.fratSemi(11))
            .foregroundColor(.fratGray)
            .padding(.horizontal, 24)
            .padding(.bottom, 6)
    }
}

// MARK: - Field box

private struct FieldBox<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.fratCard))
    }
}

// MARK: - Year picker

private struct YearPicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SchoolYear.allCases) { year in
                let isSelected = selection == year.rawValue
                Button {
                    selection = year.rawValue
                } label: {
                    Text(shortLabel(for: year))
                        .font(.fratSemi(13))
                        .foregroundColor(isSelected ? .white : .fratDark)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? Color.fratPink : Color.fratCard)
                        )
                }
            }
        }
    }

    private func shortLabel(for year: SchoolYear) -> String {
        switch year {
        case .freshman:    return "Fresh"
        case .sophomore:   return "Soph"
        case .junior:      return "Junior"
        case .senior:      return "Senior"
        case .gradStudent: return "Grad"
        }
    }
}

#Preview {
    NavigationStack {
        ProfileSetupView()
            .environmentObject(MeshManager())
    }
}

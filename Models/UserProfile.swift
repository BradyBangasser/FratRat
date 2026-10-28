//
//  UserProfile.swift
//  FratRat
//

import Foundation
import UIKit

struct UserProfile: Equatable {
    var name:                String = ""
    var college:             String = ""
    var year:                String = ""
    var bio:                 String = ""
    var photoURLs:           [String] = [] // CloudFront URLs — parallel to photoKeys
    var photoKeys:           [Data]   = [] // per-photo ChaCha20 symmetric keys
    var localPhotoFilenames: [String] = [] // on-device JPEG filenames

    private static let localPhotosKey = "fratrat.localPhotoFilenames"
    /// Older builds kept the enrollment email here; only ever deleted now.
    private static let legacyEmailKey = "fratrat.userEmail"

    // MARK: - Load from SQLite

    static func load() -> UserProfile {
        var profile = UserProfile()

        if let p = loadUserProfile() {
            profile.name      = p.name
            profile.college   = p.college
            profile.year      = p.year
            profile.bio       = p.bio
            profile.photoURLs = p.photoBlobIds
            profile.photoKeys = p.photoBlobKeys
        }

        profile.localPhotoFilenames = UserDefaults.standard
            .stringArray(forKey: localPhotosKey) ?? []
        UserDefaults.standard.removeObject(forKey: legacyEmailKey)

        return profile
    }

    // MARK: - Save to SQLite

    func save() {
        let peerProfile = PeerProfile(
            peerId:        NodeIdentity.loadOrGenerateDefault().peerIdString(),
            name:          name,
            college:       college,
            year:          year,
            bio:           bio,
            photoBlobIds:  photoURLs,
            photoBlobKeys: photoKeys,
            timestamp:     UInt64(Date().timeIntervalSince1970)
        )
        let ok = saveUserProfile(profile: peerProfile)
        if !ok { print("[UserProfile] SQLite save failed") }

        UserDefaults.standard.set(localPhotoFilenames, forKey: Self.localPhotosKey)
    }

    /// Forget the on-device profile and photos (the Rust store is wiped
    /// separately by deleteAllLocalData()).
    static func deleteLocal() {
        UserDefaults.standard.removeObject(forKey: localPhotosKey)
        UserDefaults.standard.removeObject(forKey: legacyEmailKey)
        ImageStore.deleteAll()
    }

    // MARK: - Computed

    var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !college.trimmingCharacters(in: .whitespaces).isEmpty &&
        !year.isEmpty
    }

    var initials: String {
        let parts = name.split(separator: " ")
        let chars = parts.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return chars.isEmpty ? "?" : chars.uppercased()
    }

    /// True when local photos exist that haven't been uploaded yet.
    /// MeshManager.retryPendingPhotoUploads() uses this on connect.
    var hasPendingUploads: Bool {
        photoURLs.count < localPhotoFilenames.count
    }
}

// MARK: - Year options

enum SchoolYear: String, CaseIterable, Identifiable {
    case freshman    = "Freshman"
    case sophomore   = "Sophomore"
    case junior      = "Junior"
    case senior      = "Senior"
    case gradStudent = "Grad student"

    var id: String { rawValue }
}

// MARK: - ImageStore
// Local on-device storage for the current user's own profile photos.
// Peers' photos are loaded from CloudFront via URLSession and cached
// in ImageLoader's in-memory cache — they are never written here.

struct ImageStore {
    private static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir  = docs.appendingPathComponent("ProfilePhotos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        }
        return dir
    }

    /// Save a UIImage to disk as JPEG. Returns the filename (not full path).
    static func save(_ image: UIImage, quality: CGFloat = 0.8) -> String? {
        guard let data = image.jpegData(compressionQuality: quality) else { return nil }
        let filename = "\(UUID().uuidString).jpg"
        let url = directory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            return filename
        } catch {
            print("[ImageStore] save failed: \(error)")
            return nil
        }
    }

    /// Load a UIImage from a saved filename.
    static func load(_ filename: String) -> UIImage? {
        let url = directory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Raw JPEG bytes for upload to the relay blob service.
    static func data(for filename: String) -> Data? {
        let url = directory.appendingPathComponent(filename)
        return try? Data(contentsOf: url)
    }

    /// Delete every saved photo.
    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Delete a saved photo from disk.
    static func delete(_ filename: String) {
        let url = directory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - AppSettings

struct AppSettings: Codable {
    var appearance:     AppearanceMode = .system
    var maxDistanceKm:  Double         = 50

    var darkMode: Bool {
        get { appearance == .dark }
        set { appearance = newValue ? .dark : .light }
    }

    static let key = "fratrat.appSettings"

    static func load() -> AppSettings {
        guard let data     = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: AppSettings.key)
        UserDefaults.standard.set(appearance.rawValue, forKey: "appearanceMode")
    }
}

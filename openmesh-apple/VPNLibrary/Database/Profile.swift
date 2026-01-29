//
//  Profile.swift
//  VPNLibrary
//
//  Aligned with sing-box Library/Database/Profile.swift.
//

import Foundation

public enum ProfileType: Int {
    case local = 0
    case icloud
    case remote
}

public class Profile: Identifiable, ObservableObject {
    public var id: Int64?
    public var mustID: Int64 { id! }

    @Published public var name: String
    public var order: UInt32
    public var type: ProfileType
    public var path: String
    @Published public var remoteURL: String?
    @Published public var autoUpdate: Bool
    @Published public var autoUpdateInterval: Int32
    public var lastUpdated: Date?

    public init(id: Int64? = nil, name: String, order: UInt32 = 0, type: ProfileType, path: String, remoteURL: String? = nil, autoUpdate: Bool = false, autoUpdateInterval: Int32 = 0, lastUpdated: Date? = nil) {
        self.id = id
        self.name = name
        self.order = order
        self.type = type
        self.path = path
        self.remoteURL = remoteURL
        self.autoUpdate = autoUpdate
        self.autoUpdateInterval = autoUpdateInterval
        self.lastUpdated = lastUpdated
    }
}

public struct ProfilePreview: Identifiable, Hashable {
    public let id: Int64
    public let name: String
    public var order: UInt32
    public let type: ProfileType
    public let path: String
    public let remoteURL: String?
    public let autoUpdate: Bool
    public let autoUpdateInterval: Int32
    public let lastUpdated: Date?
    public let origin: Profile

    public init(_ profile: Profile) {
        id = profile.mustID
        name = profile.name
        order = profile.order
        type = profile.type
        path = profile.path
        remoteURL = profile.remoteURL
        autoUpdate = profile.autoUpdate
        autoUpdateInterval = profile.autoUpdateInterval
        lastUpdated = profile.lastUpdated
        origin = profile
    }
}

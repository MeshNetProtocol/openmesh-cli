//
//  VPNProfileHolder.swift
//  MeshFluxIos
//
//  Holds ExtensionProfile for "MeshFlux VPN" and registers for NEVPNStatusDidChange (SFI/sing-box pattern).
//  Status is driven only by the system notification; no polling.
//  Forwards profile's objectWillChange so the view re-renders when status changes.
//

import Combine
import Foundation
import NetworkExtension
import VPNLibrary

private let meshFluxVPNDescription = "MeshFlux VPN"

@MainActor
public final class VPNProfileHolder: ObservableObject {
    @Published public private(set) var profile: ExtensionProfile?

    private var profileStatusCancellable: AnyCancellable?

    public init() {}

    /// Load the VPN profile for "MeshFlux VPN" and register for status updates.
    public func load() async {
        profileStatusCancellable = nil
        let p = await ExtensionProfile.load(localizedDescription: meshFluxVPNDescription)
        if let p {
            p.register()
            profileStatusCancellable = p.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
        }
        profile = p
    }
}

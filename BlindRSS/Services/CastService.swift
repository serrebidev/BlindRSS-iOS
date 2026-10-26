// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import Foundation
import GoogleCast
import SwiftUI
import UIKit

/// Google Cast (research round 0.1.13). The 0.1.12 audit held casting
/// for "the owner's Cast application id"; the research found Google's
/// own iOS sender guide initializes the Cast context with
/// kGCKDefaultMediaReceiverApplicationID — Google's Default Media
/// Receiver (CC1AD845), which any sender app may use with no developer
/// registration. Media casting therefore ships with no owner
/// credential. A custom receiver (branded UI, custom namespaces) would
/// still need an application id registered by the owner; nothing in
/// the desktop's Caster media flow needs one.
///
/// The SDK binary is Google's official GoogleCast.xcframework, taken
/// through the SRGSSR/google-cast-sdk Swift package (a maintained
/// packaging of Google's releases), because Google distributes the iOS
/// SDK as a CocoaPods/manual download only.
enum CastService {
    /// The player whose current media is handed to a new Cast session.
    /// Set by the app root, which owns the AudioPlayer instance.
    static weak var player: AudioPlayer?

    private static var didSetup = false

    static func setup() {
        guard !didSetup else { return }
        didSetup = true
        let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        GCKCastContext.setSharedInstanceWith(options)
        GCKCastContext.sharedInstance().sessionManager.add(CastSessionListener.shared)
    }

    /// Sends the player's current remote media to the connected
    /// receiver and pauses local playback.
    @MainActor
    static func castCurrentMedia(to session: GCKCastSession) {
        guard let player, let article = player.currentArticle,
              let media = article.mediaURL, let url = URL(string: media),
              url.scheme == "http" || url.scheme == "https",
              let client = session.remoteMediaClient else { return }
        let metadata = GCKMediaMetadata(metadataType: .generic)
        metadata.setString(article.title, forKey: kGCKMetadataKeyTitle)
        if let feedTitle = article.feed?.title {
            metadata.setString(feedTitle, forKey: kGCKMetadataKeySubtitle)
        }
        let info = GCKMediaInformationBuilder(contentURL: url)
        info.streamType = .buffered
        info.metadata = metadata
        let options = GCKMediaLoadOptions()
        options.autoplay = true
        if player.currentTime > 0 { options.playbackPosition = player.currentTime }
        _ = client.loadMedia(info.build(), with: options)
        if player.isPlaying { player.togglePlayPause() }
        let device = session.device.friendlyName ?? "Cast device"
        Announcer.announce("Casting \(article.title) to \(device).")
    }
}

/// Watches Cast sessions so a session started from the Cast button
/// picks up whatever the player is holding.
final class CastSessionListener: NSObject, GCKSessionManagerListener {
    static let shared = CastSessionListener()

    func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKCastSession) {
        Task { @MainActor in CastService.castCurrentMedia(to: session) }
    }

    func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKCastSession,
                        withError error: Error?) {
        Announcer.announce("Casting stopped.")
    }
}

/// Google's Cast button (device picker and session control), labeled
/// for VoiceOver; the framework's own dialog is accessible.
struct CastButtonView: UIViewRepresentable {
    func makeUIView(context: Context) -> GCKUICastButton {
        let button = GCKUICastButton(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        button.accessibilityLabel = "Google Cast"
        button.accessibilityHint = "Sends playback to a Chromecast or Google TV device."
        return button
    }

    func updateUIView(_ button: GCKUICastButton, context: Context) {}
}

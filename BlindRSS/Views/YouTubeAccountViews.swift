// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import SwiftUI

/// YouTube sign-in (0.1.14): the TV device-code flow. The app shows a
/// short code; the user enters it on the activation page (on any
/// device, including this one through the link) and the app polls
/// until YouTube confirms. No password is ever typed into the app.
struct YouTubeSignInView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var account = YouTubeAccount.shared
    @State private var userCode: YouTubeTVAuth.UserCode?
    @State private var status = "Contacting YouTube for a sign-in code."
    @State private var isWorking = true
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Open the YouTube activation page, sign in with your YouTube account if asked, and enter this code:")
                        .accessibilityLabel("Open the YouTube activation page, sign in with your YouTube account if asked, and enter this code.")
                    if let userCode {
                        Text(userCode.userCode)
                            .font(.title.bold())
                            .accessibilityLabel("Sign-in code: \(userCode.userCode)")
                        Link("Open Activation Page", destination: URL(string: userCode.verificationURL)!)
                            .accessibilityHint("Opens the page where the code is entered.")
                    }
                    Text(status)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(status)
                    if isWorking { ProgressView("Waiting").accessibilityLabel("Waiting for sign-in") }
                } header: {
                    Text("Sign In to YouTube").accessibilityAddTraits(.isHeader)
                }
            }
            .navigationTitle("YouTube Sign-In")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        pollTask?.cancel()
                        dismiss()
                    }
                }
            }
            .task { await begin() }
            .onDisappear { pollTask?.cancel() }
        }
    }

    private func begin() async {
        guard userCode == nil else { return }
        let code = await YouTubeTVAuth.requestUserCode()
        guard let code else {
            status = "YouTube did not answer. Check the connection and try again."
            isWorking = false
            return
        }
        userCode = code
        status = "Waiting for you to enter the code. It expires in \(code.expiresIn / 60) minutes."
        Announcer.announce("Your YouTube sign-in code is \(code.userCode). Enter it on the activation page.")
        pollTask = Task { await poll(deviceCode: code.deviceCode, interval: code.interval, expiresIn: code.expiresIn) }
    }

    /// Polls the token endpoint at the server's interval until the
    /// user confirms, the code expires, or the view goes away.
    private func poll(deviceCode: String, interval: Int, expiresIn: Int) async {
        var waited = 0
        while !Task.isCancelled, waited < expiresIn {
            try? await Task.sleep(for: .seconds(interval))
            waited += interval
            switch await YouTubeTVAuth.exchangeDeviceCode(deviceCode) {
            case .pending:
                continue
            case .success(_, let refreshToken, _):
                guard let refreshToken else {
                    status = "Sign-in finished without a refresh token. Please try again."
                    isWorking = false
                    return
                }
                account.completeSignIn(refreshToken: refreshToken)
                Announcer.announce("Signed in to YouTube. Subscriptions and Recommendations are in Search Feeds and Podcasts.")
                dismiss()
                return
            case .failed(let error):
                status = error == "expired_token" || error == "access_denied"
                    ? "That code was not confirmed in time, or was declined. Close this and try again for a new code."
                    : "Sign-in failed (\(error)). Close this and try again."
                isWorking = false
                return
            }
        }
        if !Task.isCancelled {
            status = "That code expired. Close this and try again for a new code."
            isWorking = false
        }
    }
}

/// A signed-in YouTube feed — Subscriptions or Recommendations —
/// as a video list; each video opens with its player, stream
/// playback, and transcript.
struct YouTubeFeedView: View {
    enum Kind {
        case subscriptions, recommendations
        var title: String { self == .subscriptions ? "YouTube Subscriptions" : "YouTube Recommendations" }
    }

    @State private var account = YouTubeAccount.shared
    @State private var videos: [YouTubeService.VideoResult] = []
    @State private var isLoading = true
    let kind: Kind

    var body: some View {
        List {
            ForEach(videos) { video in
                NavigationLink { VideoResultView(video: video) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.title)
                        Text([video.channel, video.durationText, video.publishedText]
                            .filter { !$0.isEmpty }.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel(video.title)
                .accessibilityValue([video.channel, video.durationText].filter { !$0.isEmpty }.joined(separator: ", "))
                .accessibilityHint("Opens this video with its player and transcript.")
            }
            if !isLoading, videos.isEmpty {
                Text("No videos were returned. Pull to refresh, or check that you are signed in.")
                    .accessibilityLabel("No videos were returned.")
            }
        }
        .overlay { if isLoading { ProgressView("Loading").accessibilityLabel("Loading") } }
        .navigationTitle(kind.title)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        videos = kind == .subscriptions ? await account.subscriptions() : await account.recommendations()
        isLoading = false
        Announcer.announce("\(videos.count) videos in \(kind.title).")
    }
}

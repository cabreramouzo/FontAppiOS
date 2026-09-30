import AVFoundation
import CoreLocation
import Photos
import SwiftUI

/// The feature tour finishes in a choice for each permission the native app uses.
/// A system request only follows a tap on its explanation; every step can be skipped.
struct WelcomeFlow: View {
    let onFinish: () -> Void
    @State private var showingPermissions = false

    var body: some View {
        Group {
            if showingPermissions {
                PermissionTutorial(onFinish: onFinish)
            } else {
                WelcomeCarousel { showingPermissions = true }
            }
        }
        .interactiveDismissDisabled()
    }
}

private struct PermissionTutorial: View {
    let onFinish: () -> Void

    @Environment(LocationService.self) private var location
    @State private var step: Step = .location
    @State private var waitingForLocation = false
    @State private var busy = false
    @State private var wantsPassingBy = false

    private enum Step {
        case location, notifications, passingBy, motion, camera, photos

        var title: String {
            switch self {
            case .location: "ios.permission.locationTitle"
            case .notifications: "ios.permission.notificationsTitle"
            case .passingBy: "ios.permission.passingTitle"
            case .motion: "ios.passingBy.motionTitle"
            case .camera: "ios.permission.cameraTitle"
            case .photos: "ios.permission.photosTitle"
            }
        }

        var detail: String {
            switch self {
            case .location: "ios.permission.locationBody"
            case .notifications: "ios.permission.notificationsBody"
            case .passingBy: "ios.permission.passingBody"
            case .motion: "ios.passingBy.motionBody"
            case .camera: "ios.permission.cameraBody"
            case .photos: "ios.permission.photosBody"
            }
        }

        var symbol: String {
            switch self {
            case .location: "location.fill"
            case .notifications: "bell.badge.fill"
            case .passingBy: "figure.walk"
            case .motion: "car.fill"
            case .camera: "camera.fill"
            case .photos: "photo.on.rectangle.angled"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "drop.fill").foregroundStyle(.blue)
                Text("FontApp").font(.headline.bold())
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 24) {
                        Spacer(minLength: 12)
                        Image(systemName: step.symbol)
                            .font(.system(size: 88, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 200, height: 200)
                            .background(LinearGradient(colors: [.blue.opacity(0.72), .blue],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                            .shadow(color: .blue.opacity(0.2), radius: 20, y: 10)
                            .accessibilityHidden(true)
                        Text(L10n.t(step.title))
                            .font(.system(size: 29, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                        Text(L10n.t(step.detail))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, 30)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
                }
                .scrollIndicators(.hidden)
            }

            Button { request() } label: {
                Text(L10n.t("ios.permission.continue"))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || waitingForLocation)

            Button(L10n.t("ios.permission.notNow")) {
                waitingForLocation = false
                advance()
            }
                .frame(maxWidth: .infinity, minHeight: 52)
                .disabled(busy)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .background(Color(.systemBackground))
        .onChange(of: location.authorization) { _, status in
            if waitingForLocation, status != .notDetermined {
                waitingForLocation = false
                advance()
            }
        }
    }

    private func request() {
        switch step {
        case .location:
            guard location.authorization == .notDetermined else { advance(); return }
            waitingForLocation = true
            location.requestIfNeeded()
        case .notifications:
            busy = true
            Task {
                await PushNotifications.shared.enable()
                busy = false
                advance()
            }
        case .passingBy:
            // This feature is optional. Its own switch remains available in Settings.
            guard location.isAuthorized else { advance(); return }
            wantsPassingBy = true
            busy = true
            Task {
                await PassingBy.shared.setEnabled(true)
                busy = false
                advance()
            }
        case .motion:
            busy = true
            Task {
                await PassingBy.shared.askMotion()
                busy = false
                advance()
            }
        case .camera:
            busy = true
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                busy = false
                advance()
            }
        case .photos:
            busy = true
            Task {
                _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                busy = false
                advance()
            }
        }
    }

    private func advance() {
        switch step {
        case .location: step = .notifications
        case .notifications:
            let push = PushNotifications.shared.status
            step = location.isAuthorized && (push == .authorized || push == .provisional) ? .passingBy : .camera
        case .passingBy: step = wantsPassingBy && PassingBy.shared.needsMotionAsk ? .motion : .camera
        case .motion: step = .camera
        case .camera: step = .photos
        case .photos: onFinish()
        }
    }
}

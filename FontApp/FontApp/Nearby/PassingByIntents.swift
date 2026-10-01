import AppIntents

/// A Focus can silence the passing-by notices (Settings > Focus > Work > Focus filters).
/// iOS runs this when the Focus starts and again, with the default values, when it ends:
/// the default must therefore be "not silenced".
struct PassingByFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "ios.intent.focusTitle"
    static let description: IntentDescription? = IntentDescription("ios.intent.focusDescription")

    @Parameter(title: "ios.intent.focusMute", default: false)
    var mute: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: mute ? "ios.intent.focusMuted" : "ios.intent.focusAllowed")
    }

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(mute, forKey: PassingBy.focusMutedKey)
        return .result()
    }
}

extension PassingByPause: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "ios.intent.pauseLength"
    static let caseDisplayRepresentations: [PassingByPause: DisplayRepresentation] = [
        .day: "ios.passingBy.pauseDay",
        .week: "ios.passingBy.pauseWeek",
        .untilResumed: "ios.passingBy.pauseUntilResumed",
    ]
}

/// "Pause fountain notices", for Shortcuts and Siri: e.g. an automation on joining home Wi‑Fi.
struct PausePassingByIntent: AppIntent {
    static let title: LocalizedStringResource = "ios.intent.pauseTitle"
    static let description = IntentDescription("ios.intent.pauseDescription")

    @Parameter(title: "ios.intent.pauseLength", default: .day)
    var length: PassingByPause

    func perform() async throws -> some IntentResult & ProvidesDialog {
        PassingBy.shared.pause(length)
        return .result(dialog: IntentDialog(stringLiteral: L10n.t("ios.intent.pausedDialog")))
    }
}

struct ResumePassingByIntent: AppIntent {
    static let title: LocalizedStringResource = "ios.intent.resumeTitle"
    static let description = IntentDescription("ios.intent.resumeDescription")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        PassingBy.shared.resume()
        return .result(dialog: IntentDialog(stringLiteral: L10n.t("ios.intent.resumedDialog")))
    }
}

struct FontAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PausePassingByIntent(),
                    phrases: ["Pausa els avisos de fonts a \(.applicationName)"],
                    shortTitle: "ios.intent.pauseTitle", systemImageName: "pause.circle")
        AppShortcut(intent: ResumePassingByIntent(),
                    phrases: ["Reprèn els avisos de fonts a \(.applicationName)"],
                    shortTitle: "ios.intent.resumeTitle", systemImageName: "play.circle")
    }
}

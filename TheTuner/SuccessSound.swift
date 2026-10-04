import AudioToolbox
import Foundation

/// System UI sounds respect the ringer setting and don't reconfigure the recording session.
@MainActor final class SuccessSound {
    private var stringSound: SystemSoundID = 0
    private var completeSound: SystemSoundID = 0
    init() {
        if let url = Bundle.main.url(forResource: "string-tuned", withExtension: "wav") {
            AudioServicesCreateSystemSoundID(url as CFURL, &stringSound)
        }
        if let url = Bundle.main.url(forResource: "all-tuned", withExtension: "wav") {
            AudioServicesCreateSystemSoundID(url as CFURL, &completeSound)
        }
        assert(stringSound != 0 && completeSound != 0, "Bundled tuning chimes must be valid system sounds")
    }
    deinit {
        if stringSound != 0 { AudioServicesDisposeSystemSoundID(stringSound) }
        if completeSound != 0 { AudioServicesDisposeSystemSoundID(completeSound) }
    }
    func play(complete: Bool, finished: @escaping () -> Void) -> Bool {
        let sound = complete ? completeSound : stringSound
        guard sound != 0 else { return false }
        AudioServicesPlaySystemSoundWithCompletion(sound, finished)
        return true
    }
}

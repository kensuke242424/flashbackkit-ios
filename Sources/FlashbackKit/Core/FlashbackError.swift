import Foundation

public enum FlashbackError: Error {
    case notImplemented
    case recordingUnavailable
    case clipTrimFailed
    case slackPostFailed
    case photoLibraryUnauthorized
}

#if canImport(Photos)
import Photos

/// 書き出したクリップ（mp4）を端末の写真ライブラリ（カメラロール）に保存する。
///
/// `Photos` は Apple 標準フレームワークのため依存ゼロ方針を崩さない。
/// 重要: ホストアプリの Info.plist に `NSPhotoLibraryAddUsageDescription` が必須。
/// 無いと権限要求の時点でシステムがアプリを終了させる。
enum PhotoLibrarySaver {

    /// クリップを写真ライブラリへ追加する。権限は最小（addOnly）で要求する。
    /// 失敗（権限拒否・ファイル不在・保存エラー）は throw する。上位はログのみで継続させる想定。
    static func save(_ url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FlashbackError.recordingUnavailable
        }

        let status = await requestAddOnlyAuthorization()
        guard status == .authorized || status == .limited else {
            throw FlashbackError.photoLibraryUnauthorized
        }

        try await PHPhotoLibrary.shared().performChanges {
            // creationRequestForAssetFromVideo は optional 返し。nil（読込不可など）の場合は
            // 変更を行わない（performChanges 側がエラーで返す）。
            _ = PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    private static func requestAddOnlyAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
#endif

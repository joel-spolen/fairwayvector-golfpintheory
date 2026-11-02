import Foundation

/// Plain-language text for any error shown to the golfer. App error types carry
/// curated descriptions; system, file, decoding and SDK errors are never shown verbatim.
nonisolated enum UserFacingError {
    static func message(_ error: any Error) -> String {
        switch error {
        case is PinTheoryAuthError, is AccountSyncError, is GolfAPIError, is TerrainError,
             is CourseBuilderError, is CourseWeatherError, is OverpassError, is RoundStorageError,
             is SupabaseProviderError, is HybridPredictorError, is AtmosphereError:
            error.localizedDescription
        case is URLError:
            L("We couldn't connect. Check your internet connection and try again.")
        default:
            L("Something went wrong. Please try again.")
        }
    }
}

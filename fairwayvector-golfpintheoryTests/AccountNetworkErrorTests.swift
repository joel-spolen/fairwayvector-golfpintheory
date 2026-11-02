import Foundation
import Testing
@testable import fairwayvector_golfpintheory

struct AccountNetworkErrorTests {
    @Test(arguments: [-1001, -1003, -1004, -1005, -1006, -1200, -1202, -1011, -1022])
    func networkMessagesExposeNoCodeOrUnderlyingDetail(code: Int) {
        let underlying = URLError(URLError.Code(rawValue: code), userInfo: [
            NSURLErrorFailingURLErrorKey: URL(string: "https://private.example/?password=secret")!,
            NSLocalizedDescriptionKey: "secret private provider detail"
        ])
        let mapped = PinTheoryAuthError.networkError(underlying)
        #expect(mapped == .connectionFailure(code))
        let message = mapped.localizedDescription
        #expect(!message.contains(String(code)))
        #expect(!message.contains("private.example"))
        #expect(!message.contains("secret"))
        #expect(!message.contains("password="))
    }

    @Test func offlineAndCancellationKeepExistingCategories() {
        #expect(PinTheoryAuthError.networkError(URLError(.notConnectedToInternet)) == .networkUnavailable)
        #expect(!PinTheoryAuthError.networkUnavailable.localizedDescription.contains("-1009"))
        #expect(PinTheoryAuthError.networkError(URLError(.cancelled)) == .cancelled)
    }

    @Test func diagnosticDoesNotIncludeUnderlyingProviderDetails() {
        let error = URLError(.notConnectedToInternet, userInfo: [
            NSURLErrorFailingURLErrorKey: URL(string: "https://private.example/?password=secret")!,
            NSLocalizedDescriptionKey: "private provider message secret"
        ])
        let summary = PinTheoryNetworkDiagnostics.describe(error)
        #expect(summary.contains("-1009"))
        #expect(summary.contains("not supplied by iOS"))
        #expect(!summary.contains("private.example"))
        #expect(!summary.contains("secret"))
        #expect(!summary.contains("password"))
    }

    @MainActor @Test func systemErrorsAreNeverShownVerbatim() {
        let file = CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: "/private/rounds-v1.json"])
        #expect(UserFacingError.message(file) == L("Something went wrong. Please try again."))
        #expect(!UserFacingError.message(URLError(.timedOut)).contains("-1001"))
        #expect(UserFacingError.message(RoundStorageError.saveFailed) == RoundStorageError.saveFailed.localizedDescription)
        let provider = SupabaseProviderError.httpStatus(500, code: "internal", message: "private server detail")
        #expect(!UserFacingError.message(provider).contains("private"))
    }
}
package enum ReloadDisposition: Sendable, Equatable {
    case applied
    case pending
    case rejected
    case failed
}

/// Outcome of applying a configuration to the running session.
package struct ReloadResult: Sendable {
    package let success: Bool
    package let response: String?
    package let errorMessage: String?
    package let disposition: ReloadDisposition

    package var isSuccess: Bool {
        disposition == .applied
    }

    package init(
        success: Bool,
        response: String?,
        errorMessage: String?,
        disposition: ReloadDisposition? = nil
    ) {
        self.success = success
        self.response = response
        self.errorMessage = errorMessage
        self.disposition = disposition ?? (success ? .applied : .failed)
    }
}

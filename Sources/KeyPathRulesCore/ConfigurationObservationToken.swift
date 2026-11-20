/// A token representing a configuration observation that can be cancelled.
public struct ConfigurationObservationToken {
    private let cancellationHandler: () -> Void

    init(cancellationHandler: @escaping () -> Void) {
        self.cancellationHandler = cancellationHandler
    }

    /// Cancels the configuration observation.
    public func cancel() {
        cancellationHandler()
    }
}

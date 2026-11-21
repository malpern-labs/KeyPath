/// How an `AdmissionVerdict` reads to a person: one title, one explanation, and
/// the choices its fixes offer. Dialogs, toasts and the CLI all render from this,
/// so a reason is worded once (phase 4b of the admission review).
public struct AdmissionPresentation: Equatable, Sendable {
    public struct Option: Equatable, Identifiable, Sendable {
        public let subject: AdmissionSubject
        public let label: String
        public let fix: AdmissionVerdict.Fix
        package init(subject: AdmissionSubject, label: String, fix: AdmissionVerdict.Fix) {
            self.subject = subject
            self.label = label
            self.fix = fix
        }

        public var id: String {
            "\(subject)|\(label)"
        }
    }

    public let title: String
    public let explanation: String
    public let options: [Option]

    package init(title: String, explanation: String, options: [Option]) {
        self.title = title
        self.explanation = explanation
        self.options = options
    }
}

import Foundation
import KeyPathCore
import KeyPathRulesCore

public extension ConfigurationService {
    /// Parse configuration from string content
    func parseConfigurationFromString(_ content: String) throws -> KanataConfiguration {
        // Use the existing validate method which handles parsing
        try validate(content: content)
    }
}

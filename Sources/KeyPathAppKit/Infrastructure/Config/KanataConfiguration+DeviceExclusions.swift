import KeyPathRulesCore

extension KanataConfiguration {
    #if os(macOS)
        /// Parse the output of `kanata --list` and return device identifiers suitable for
        /// `macos-dev-names-exclude`. Kept as a pure function for unit testing.
        /// Used by legacy callers — new code should use `DeviceEnumerationService.parseAllDevices`.
        static func parseExcludedMacOSDeviceNames(fromKanataList output: String) -> [String] {
            let devices = DeviceEnumerationService.parseAllDevices(fromKanataList: output)
            var results = Set<String>()
            for device in devices where device.isVirtualHID {
                results.insert(device.hash)
                results.insert(device.productKey)
            }
            return results.sorted()
        }
    #endif
}

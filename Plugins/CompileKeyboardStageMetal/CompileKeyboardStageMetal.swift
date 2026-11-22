import Foundation
import PackagePlugin

@main
struct CompileKeyboardStageMetal: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: any Target
    ) async throws -> [Command] {
        let shader = target.directoryURL
            .appendingPathComponent("UI/KeyboardStage/Metal/KeyboardStage.metal")
        let library = context.pluginWorkDirectoryURL
            .appendingPathComponent("default.metallib")
        // SwiftPM sets TOOLCHAINS for plugin commands. xcrun needs to resolve the separately
        // installed Metal toolchain itself, so remove that override for this invocation.
        let env = URL(fileURLWithPath: "/usr/bin/env")

        return [
            .buildCommand(
                displayName: "Compile KeyboardStage default.metallib",
                executable: env,
                arguments: [
                    "-u", "TOOLCHAINS",
                    "/usr/bin/xcrun",
                    "-sdk", "macosx", "metal",
                    shader.path,
                    "-o", library.path,
                ],
                inputFiles: [shader],
                outputFiles: [library]
            ),
        ]
    }
}

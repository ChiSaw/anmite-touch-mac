import CoreGraphics
import Foundation
import TouchMonitorPOC

struct CLIConfiguration {
    var listOnly = false
    var dumpRaw = false
    var probeVendor = false
    var activateVendor = false
    var targetVendorID: Int?
    var targetProductID: Int?
    var targetDisplayID: CGDirectDisplayID?
    var enableInjection = false
    var requestPermissions = false

    static func parse(arguments: [String]) -> CLIConfiguration {
        var config = CLIConfiguration()
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--list":
                config.listOnly = true
            case "--dump-raw":
                config.dumpRaw = true
            case "--probe-vendor":
                config.probeVendor = true
            case "--activate-vendor":
                config.activateVendor = true
            case "--inject":
                config.enableInjection = true
            case "--request-permissions":
                config.requestPermissions = true
            case "--vendor-id":
                config.targetVendorID = iterator.next().flatMap(Int.init)
            case "--product-id":
                config.targetProductID = iterator.next().flatMap(Int.init)
            case "--display-id":
                config.targetDisplayID = iterator.next().flatMap(UInt32.init)
            default:
                break
            }
        }

        return config
    }
}

let cliConfig = CLIConfiguration.parse(arguments: Array(CommandLine.arguments.dropFirst()))
let runtimeConfig = TouchMonitorConfiguration(
    listOnly: cliConfig.listOnly,
    dumpRaw: cliConfig.dumpRaw,
    probeVendor: cliConfig.probeVendor,
    activateVendor: cliConfig.activateVendor,
    targetVendorID: cliConfig.targetVendorID,
    targetProductID: cliConfig.targetProductID,
    targetDisplayID: cliConfig.targetDisplayID,
    enableInjection: cliConfig.enableInjection,
    requestPermissions: cliConfig.requestPermissions
)

let service = TouchMonitorService(config: runtimeConfig) { line in
    print(line)
}

do {
    try service.start()
    RunLoop.current.run()
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}

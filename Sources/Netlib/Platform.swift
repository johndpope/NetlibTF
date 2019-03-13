//******************************************************************************
//  Created by Edward Connell on 8/20/16
//  Copyright © 2016 Connell Research. All rights reserved.
//
//  Platform (singleton)
//		services
//			ComputeService (cpu, cuda, amd, cloud, ...)
//				devices
//					ComputeDevice (gpu:0, gpu:1, ...)
//						DeviceStream
//						DeviceArray
import Foundation

//==============================================================================
// Platform
/// The root service to enumerate and select compute services and devices
final public class Platform: ObjectTracking, Logging {
    //--------------------------------------------------------------------------
    // properties
    public static let shared: Platform = { return Platform() }()
    public var defaultDevice: ComputeDevice
    public var defaultDeviceCount = 1
    public var devicePriority: [Int]?
    public var servicePriority = ["cuda", "cpu"]

    // object tracking
    public private(set) var trackingId = 0
    public var namePath = String(describing: Platform.self)

    // logging
    public let context: EvaluationContext?
    public var logLevel = LogLevel.error
    public let nestingLevel = 0

    // cpu, cuda, etc...
    public private(set) var services: [String : ComputeService]

    //--------------------------------------------------------------------------
    // plugIns
    public static var plugInBundles: [Bundle] = {
        var bundles = [Bundle]()
        if let dir = Bundle.main.builtInPlugInsPath {
            let paths = Bundle.paths(forResourcesOfType: "bundle", inDirectory: dir)
            for path in paths {
                bundles.append(Bundle(url: URL(fileURLWithPath: path))!)
            }
        }
        return bundles
    }()

    //--------------------------------------------------------------------------
    // initializer
    private init() {
        do {
            // add cpu service by default
            try add(service: CpuComputeService(log: currentLog))
            #if os(Linux)
            try add(service: CudaComputeService(log: currentLog))
            #endif

            for bundle in ComputePlatform.plugInBundles {
                try bundle.loadAndReturnError()
//			var unloadBundle = false

                if let serviceType = bundle.principalClass as? ComputeService.Type {
                    // create the service
                    let service = try serviceType.init(log: currentLog)

                    if willLog(level: .diagnostic) {
                        diagnostic("Loaded compute service '\(service.name)'." +
                                " ComputeDevice count = \(service.devices.count)", categories: .setup)
                    }

                    if service.devices.count > 0 {
                        // add plugin service
                        add(service: service)
                    } else {
                        if willLog(level: .warning) {
                            writeLog("Compute service '\(service.name)' successfully loaded, " +
                                    "but reported devices = 0, so service is unavailable",
                                    level: .warning)
                        }
//					unloadBundle = true
                    }
                }
                // TODO: we should call bundle unload here if there were no devices
                // however simply calling bundle.load() then bundle.unload() making no
                // references to objects inside, later causes an exception in the code.
                // Very strange
//			if unloadBundle { bundle.unload() }
            }

            // try to exact match the service request
            let requestedDevice = devicePriority?[0] ?? 0
            for serviceName in servicePriority where _defaultDevice == nil {
                _defaultDevice = requestDevice(serviceName: serviceName,
                        deviceId: requestedDevice,
                        allowSubstitute: false)
            }

            // if the search failed, then allow substitutes
            if _defaultDevice == nil {
                let services = servicePriority + ["cpu"]
                for serviceName in services where _defaultDevice == nil {
                    _defaultDevice = requestDevice(serviceName: serviceName, deviceId: 0,
                            allowSubstitute: false)
                }
            }

            // we have to find something
            assert(_defaultDevice != nil)
            if willLog(level: .status) {
                writeLog("default device: \(defaultDevice.name)" +
                        "   id: \(defaultDevice.service.name).\(defaultDevice.id)",
                        level: .status)
            }
        } catch {
            writeLog(String(describing: error))
        }
    }

    //--------------------------------------------------------------------------
    // add(service
    public func add(service: ComputeService) {
        service.id = services.count
        services[service.name] = service
    }

    //--------------------------------------------------------------------------
    // requestStreams
    //	This will try to match the requested service and device ids returning
    // substitutes if needed.
    //
    // If no service name is specified, then the default is used.
    // If no ids are specified, then one stream per defaultDeviceCount is returned
    public func requestStreams(label: String,
                               serviceName: String? = nil,
                               deviceIds: [Int]? = nil) throws -> [DeviceStream]
    {
        let serviceName = serviceName ?? defaultDevice.service.name
        let maxDeviceCount = min(defaultDeviceCount, defaultDevice.service.devices.count)
        let ids = deviceIds ?? [Int](0..<maxDeviceCount)

        return try ids.map {
            let device = requestDevice(serviceName: serviceName,
                    deviceId: $0, allowSubstitute: true)!
            return try device.createStream(label: label)
        }
    }

    //--------------------------------------------------------------------------
    // requestDevices
    public func requestDevices(serviceName: String?, deviceIds: [Int]) -> [ComputeDevice] {
        // if no serviceName is specified then return the default
        let serviceName = serviceName ?? defaultDevice.service.name
        return deviceIds.map {
            requestDevice(serviceName: serviceName,
                    deviceId: $0, allowSubstitute: true)!
        }
    }

    //--------------------------------------------------------------------------
    // requestDevice
    /// This tries to satisfy the device requested, but if not available will
    /// return a suitable alternative. In the case of an invalid string, an
    /// error will be reported, but no exception will be thrown
    public func requestDevice(serviceName: String, deviceId: Int,
                              allowSubstitute: Bool) -> ComputeDevice?
    {
        if let service = services[serviceName] {
            if deviceId < service.devices.count {
                return service.devices[deviceId]
            } else if allowSubstitute {
                return service.devices[deviceId % service.devices.count]
            } else {
                return nil
            }
        } else if allowSubstitute {
            let service = services[defaultDevice.service.name]!
            return service.devices[deviceId % service.devices.count]
        } else {
            return nil
        }
    }
} // ComputePlatform
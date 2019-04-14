//******************************************************************************
//  Created by Edward Connell on 3/5/16
//  Copyright © 2016 Connell Research. All rights reserved.
//
import Foundation

//==============================================================================
/// ComputePlatform
/// this represents the root for managing all services, devices, and streams
/// on a platform. There is one local instance per process, and possibly
/// many remote instances.
public protocol ComputePlatform : ObjectTracking, Logging {
    //--------------------------------------------------------------------------
    // class members
    /// global shared instance
    static var local: Platform { get }
    /// a stream selected based on `servicePriority` and `deviceIdPriority`
    static var defaultStream: DeviceStream { get }
    
    // instance members
    /// a device automatically selected based on service priority
    var defaultDevice: ComputeDevice { get }
    /// the default number of devices to spread a set of streams across
    /// a value of -1 specifies all available devices within the service
    var defaultDevicesToAllocate: Int { get set }
    /// ordered list of device ids specifying the order for auto selection
    var deviceIdPriority: [Int] { get set }
    /// location of dynamically loaded service modules
    var serviceModuleDirectory: URL { get set }
    /// ordered list of service names specifying the order for auto selection
    var servicePriority: [String] { get set }
    /// a dynamically loaded collection of available compute services.
    /// The "cpu" service will always be available
    var services: [String : ComputeService] { get }
    /// the root log
    var log: Log { get set }
    
    //--------------------------------------------------------------------------
    /// createStreams will try to match the requested service name and
    /// device ids returning substitutions if needed to fulfill the request
    ///
    /// Parameters
    /// - Parameter name: a text label assigned to the stream for logging
    /// - Parameter serviceName: (cpu, cuda, tpu, ...)
    ///   If no service name is specified, then the default is used.
    /// - Parameter deviceIds: (0, 1, 2, ...)
    ///   If no ids are specified, then one stream per defaultDeviceCount
    ///   is returned. If device ids are specified that are greater than
    ///   the number of available devices, then id % available will be used.
    func createStreams(name: String,
                       serviceName: String?,
                       deviceIds: [Int]?) throws -> [DeviceStream]
    
    //--------------------------------------------------------------------------
    /// open
    /// this is a placeholder. Additional parameters will be needed for
    /// credentials, timeouts, etc...
    ///
    /// - Parameter url: the location of the remote platform
    /// - Returns: a reference to the remote platform, which can be used
    ///   to query resources and create remote streams.
    static func open(platform url: URL) throws -> ComputePlatform
    
    //--------------------------------------------------------------------------
    /// requestDevices
    /// - Parameter deviceIds: an array of selected device ids
    /// - Parameter serviceName: an optional service name to allocate
    ///   the devices from.
    /// - Returns: the requested devices from the requested service
    ///   substituting if needed based on `servicePriority`
    ///   and `deviceIdPriority`
    func requestDevices(deviceIds: [Int],
                        serviceName: String?) -> [ComputeDevice]
    
}

//==============================================================================
/// ComputeService
/// a compute service represents category of installed devices on the platform,
/// such as (cpu, cuda, tpu, ...)
public protocol ComputeService: ObjectTracking, Logging {
    /// a collection of available devices
    var devices: [ComputeDevice] { get }
    /// the service id
    var id: Int { get set }
    /// the service name used for `servicePriority` and logging
    var name: String { get }
    
    /// required initializer to support dynamiclly loaded services
    init(logging: LogInfo) throws
}

//==============================================================================
/// ComputeDevice
/// a compute device represents a physical service device installed
/// on the platform
public protocol ComputeDevice: ObjectTracking, Logging {
    //-------------------------------------
    // properties
    /// a dictionary of device specific attributes describing the device
    var attributes: [String: String] { get }
    /// the amount of free memory currently available on the device
    var availableMemory: UInt64 { get }
    /// the id of the device for example gpu:0
    var id: Int { get }
    /// the maximum number of threads supported per block
    var maxThreadsPerBlock: Int { get }
    /// the name of the device
    var name: String { get }
    /// the service this device belongs to
    var service: ComputeService! { get }
    /// the maximum amount of time allowed for an operation to complete
    var timeout: TimeInterval? { get set }
    /// the type of memory addressing this device uses
    var memoryAddressing: MemoryAddressing { get }
    /// current percent of the device utilized
    var utilization: Float { get }

    //-------------------------------------
    // device resource functions
    /// creates an array on this device
    func createArray(count: Int) throws -> DeviceArray
    /// creates a named command stream for this device
    func createStream(name: String) throws -> DeviceStream
}

public enum MemoryAddressing { case unified, discreet }

//==============================================================================
// DeviceArray
//    This represents a device data array
public protocol DeviceArray: ObjectTracking, Logging {
    //-------------------------------------
    // properties
    /// the device where this array is allocated
    var device: ComputeDevice { get }
    /// a pointer to the memory on the device
    var data: UnsafeMutableRawPointer { get }
    /// the size of the device memory in bytes
    var count: Int { get }
    /// the array edit version number used for replication and synchronization
    var version: Int { get set }

    //-------------------------------------
    // functions
    /// clears the array to zero
    func zero(using stream: DeviceStream?) throws
    /// asynchronously copies the contents of another device array
    func copyAsync(from other: DeviceArray, using stream: DeviceStream) throws
    /// asynchronously copies the contents of a memory buffer
    func copyAsync(from buffer: UnsafeRawBufferPointer,
                   using stream: DeviceStream) throws
    /// copies the contents to a memory buffer synchronously
    func copy(to buffer: UnsafeMutableRawBufferPointer,
              using stream: DeviceStream) throws
    /// copies the contents to a memory buffer asynchronously
    func copyAsync(to buffer: UnsafeMutableRawBufferPointer,
                   using stream: DeviceStream) throws
}

//==============================================================================
// StreamEvent
/// Stream events are queued to enable stream synchronization
public protocol StreamEvent: ObjectTracking, Logging {
    /// is `true` if the even has occurred, used for polling
    var occurred: Bool { get }
    
    // TODO: consider adding time outs for failed remote events
    init(logging: LogInfo, options: StreamEventOptions) throws
}

public struct StreamEventOptions: OptionSet {
    public init(rawValue: Int) { self.rawValue = rawValue }
    public let rawValue: Int
    public static let hostSync     = StreamEventOptions(rawValue: 1 << 0)
    public static let timing       = StreamEventOptions(rawValue: 1 << 1)
    public static let interprocess = StreamEventOptions(rawValue: 1 << 2)
}

public enum StreamEventError: Error {
    case timedOut
}

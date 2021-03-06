//******************************************************************************
//  Created by Edward Connell on 3/21/16
//  Copyright © 2016 Connell Research. All rights reserved.
//
import Foundation
import Dispatch

public class CpuDevice: LocalComputeDevice {
    //--------------------------------------------------------------------------
    // properties
    public private(set) var trackingId = 0
    public let attributes = [String : String]()
    public var deviceArrayReplicaKey: DeviceArrayReplicaKey
    public let id: Int
    public var logInfo: LogInfo
    public var maxThreadsPerBlock: Int { return 1 }
    public let name: String
    public weak var service: ComputeService!
    private let streamId = AtomicCounter(value: -1)
    public var timeout: TimeInterval
    public let memoryAddressing: MemoryAddressing
    public var utilization: Float = 0
    public var deviceErrorHandler: DeviceErrorHandler?
    public var _lastError: Error? = nil
    public var _errorMutex: Mutex = Mutex()

    // TODO this should be currently available and not physicalMemory
    public lazy var availableMemory: UInt64 = {
        return ProcessInfo().physicalMemory
    }()

    //--------------------------------------------------------------------------
	// initializers
	public init(service: ComputeService,
                deviceId: Int,
                logInfo: LogInfo,
                memoryAddressing: MemoryAddressing,
                timeout: TimeInterval) {
        self.name = "cpu:\(deviceId)"
		self.logInfo = logInfo
		self.id = deviceId
		self.service = service
        self.timeout = timeout
        self.memoryAddressing = memoryAddressing
        deviceArrayReplicaKey =
            DeviceArrayReplicaKey(platformId: service.platform!.id,
                                  serviceId: service.id, deviceId: id)

		// devices are statically held by the Platform.service
        trackingId = ObjectTracker.global
            .register(self, namePath: logNamePath, isStatic: true)
	}
	deinit { ObjectTracker.global.remove(trackingId: trackingId) }

    //--------------------------------------------------------------------------
	// createArray
	//	This creates memory on the device
	public func createArray(count: Int) throws -> DeviceArray {
        return CpuDeviceArray(device: self, count: count)
	}
    
    //--------------------------------------------------------------------------
    // createMutableReferenceArray
    /// creates a device array from a uma buffer.
    public func createMutableReferenceArray(
        buffer: UnsafeMutableRawBufferPointer) -> DeviceArray {
        return CpuDeviceArray(device: self, buffer: buffer)
    }
    
    //--------------------------------------------------------------------------
    // createReferenceArray
    /// creates a device array from a uma buffer.
    public func createReferenceArray(buffer: UnsafeRawBufferPointer)
        -> DeviceArray
    {
        return CpuDeviceArray(device: self, buffer: buffer)
    }

    //--------------------------------------------------------------------------
	// createStream
	public func createStream(name streamName: String) -> DeviceStream {
        let id = streamId.increment()
        let streamName = "\(streamName):\(id)"
        return CpuStream(logInfo: logInfo.flat(streamName),
                         device: self, name: streamName, id: id)
	}
} // CpuDevice



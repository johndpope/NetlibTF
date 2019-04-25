//******************************************************************************
//  Created by Edward Connell on 3/21/16
//  Copyright © 2016 Connell Research. All rights reserved.
//
import Foundation
import Dispatch

//==============================================================================
/// TensorArray
/// The TensorArray object is a flat array of scalars used by the TensorView.
/// It is responsible for replication and syncing between devices.
/// It is not created or directly used by end users.
final public class TensorArray: ObjectTracking, Logging {
    // properties
    /// used by TensorViews to synchronize access to this object
    public let accessQueue = DispatchQueue(label: "TensorArray.accessQueue")
    ///
    public var autoReleaseUmaBuffer = false
    /// testing: `true` if the last access caused the contents of the
    /// buffer to be copied
    public private(set) var lastAccessCopiedBuffer = false
    /// testing: is `true` if the last data access caused the view's underlying
    /// tensorData object to be copied. It's stored here instead of on the
    /// view, because the view is immutable when taking a read only pointer
    public var lastAccessMutatedView: Bool = false
    /// the object tracking id
    public private(set) var trackingId = 0
    /// name label used for logging
    public let name: String
    
    // local
    private let streamRequired = "stream is required for device data transfers"
    private let isReadOnlyReference: Bool

    //-----------------------------------
    /// The hostBuffer is the app thread synced data array.
    ///
    /// The hostBuffer points to the host data used by this object. Usually it
    /// will point to the hostArray, but it can also point to a read only
    /// buffer specified during init. The purpose is to use data from something
    /// like a memory mapped file without copying it.
    private var hostVersion = -1
    private var hostBuffer: UnsafeMutableRawBufferPointer!
    public let byteCount: Int
    public let elementCount: Int

    //-----------------------------------
    // stream sync
    private var _streamSyncEvent: StreamEvent!
    private func getSyncEvent(using stream: DeviceStream) throws -> StreamEvent{
        if _streamSyncEvent == nil {
            _streamSyncEvent = try stream.createEvent(options: [])
        }
        return _streamSyncEvent
    }

    // this can either point to the hostArray or to the deviceArray
    // depending on the location of the master
    private var deviceDataPointer: UnsafeMutableRawPointer!

    // this is indexed by [service.id][device.id]
    // and contains a lazy allocated array on each device,
    // which is a replica of the current master
    private var deviceArrays = [[ArrayInfo?]]()

    public class ArrayInfo {
        public init(array: DeviceArray, stream: DeviceStream) {
            self.array = array
            self.stream = stream
        }

        public let array: DeviceArray
        // stream is tracked for synchronous cleanup (deinit) of the array
        public var stream: DeviceStream
    }

    // whenever a buffer write pointer is taken, the associated DeviceArray
    // becomes the master copy for replication. Synchronization across threads
    // is still required for taking multiple write pointers, however
    // this does automatically synchronize data migrations.
    // A value of nil means that the master is the umaBuffer
    public private(set) var master: ArrayInfo?

    // this is incremented each time a write pointer is taken
    // all replicated buffers will stay in sync with this version
    private var masterVersion = -1

    //--------------------------------------------------------------------------
    // initializers

    // Empty
    public convenience init() {
        self.init(type: UInt8.self, count: 0, name: "")
    }

    //----------------------------------------
    // All initializers retain the data except this one
    // which creates a read only reference to avoid unnecessary copying from
    // a read only data object
    public init(readOnlyReferenceTo buffer: UnsafeRawBufferPointer,
                name: String) {
        // store
        isReadOnlyReference = true
        elementCount = buffer.count
        byteCount = buffer.count
        masterVersion = 0
        hostVersion = 0
        self.name = name

        // we won't ever actually mutate in this case
        hostBuffer = UnsafeMutableRawBufferPointer(
            start: UnsafeMutableRawPointer(OpaquePointer(buffer.baseAddress)),
            count: buffer.count)
        register()
    }

    //----------------------------------------
    // copy from buffer
    public init(buffer: UnsafeRawBufferPointer, name: String) {
        isReadOnlyReference = false
        elementCount = buffer.count
        byteCount = buffer.count
        self.name = name

        do {
            _ = try readWriteHostBuffer()
                .initializeMemory(as: UInt8.self, from: buffer)
        } catch {
            // TODO: what do we want to do here when it should never fail
        }
        assert(hostVersion == 0 && masterVersion == 0)
        register()
    }

    //----------------------------------------
    // create new array based on scalar size
    public init<Scalar>(type: Scalar.Type, count: Int, name: String) {
        isReadOnlyReference = false
        self.elementCount = count
        self.byteCount = count * MemoryLayout<Scalar>.size
        self.name = name
        register()
    }
    
    //----------------------------------------
    // object lifetime tracking for leak detection
    private func register() {
        trackingId = ObjectTracker.global
            .register(self, namePath: logNamePath,
                      supplementalInfo: "byteCount: \(byteCount)")

        if byteCount > 0 {
            diagnostic("\(createString) \(name)(\(trackingId)) " +
                    "elements[\(elementCount)]", categories: .dataAlloc)
        }
    }

    //----------------------------------------
    deinit {
        do {
            // synchronize with all streams that have accessed these arrays
            // before freeing them
            for sid in 0..<deviceArrays.count {
                for devId in 0..<deviceArrays[sid].count {
                    if let info = deviceArrays[sid][devId] {
                        try info.stream.blockCallerUntilComplete()
                    }
                }
            }
        } catch {
            writeLog(String(describing: error))
        }
        ObjectTracker.global.remove(trackingId: trackingId)

        if byteCount > 0 {
            diagnostic("\(releaseString) \(name)(\(trackingId)) " +
                "elements[\(elementCount)]", categories: .dataAlloc)
        }
    }

    //----------------------------------------
    // init from other TensorArray
    public init(withContentsOf other: TensorArray,
                using stream: DeviceStream?) throws {
        // init
        isReadOnlyReference = other.isReadOnlyReference
        byteCount = other.byteCount
        elementCount = other.byteCount
        name = other.name
        masterVersion = 0
        hostVersion = masterVersion
        register()
        
        diagnostic(
            "\(createString) \(name)(\(trackingId)) init" +
            "\(setText(" copying ", color: .blue))" +
            "TensorArray(\(other.trackingId)) elements[\(elementCount)]",
            categories: [.dataAlloc, .dataCopy])
        
        if isReadOnlyReference {
            // point to external data buffer, such as memory mapped file
            assert(master == nil)
            hostBuffer = other.hostBuffer
            
        } else if let stream = stream {
            // get new array for the target stream's device location
            let arrayInfo = try getArray(for: stream)
            let array     = arrayInfo.array
            array.version = masterVersion
            
            if let otherMaster = other.master {
                // sync streams and copy
                try stream.sync(with: otherMaster.stream,
                                event: getSyncEvent(using: stream))
                try array.copyAsync(from: otherMaster.array, using: stream)

                diagnostic("\(copyString) \(name)(\(trackingId)) " +
                    "\(otherMaster.stream.device.name)" +
                    "\(setText(" --> ", color: .blue))" +
                    "\(stream.device.name)_s\(stream.id) " +
                    "elements[\(elementCount)]",
                    categories: .dataCopy)
            } else {
                // uma to device
                try array.copyAsync(from: other.readOnlyHostBuffer(),
                                    using: stream)
            }
            
            // set the master
            master = arrayInfo
            
        } else {
            // get pointer to this array's umaBuffer
            let buffer = try readWriteHostBuffer()
            
            if let otherMaster = other.master {
                // synchronous device to umaArray
                try otherMaster.array.copy(to: buffer, using: otherMaster.stream)
                
            } else {
                // umaArray to umaArray
                try buffer.copyMemory(from: other.readOnlyHostBuffer())
            }
        }
    }
    
    //--------------------------------------------------------------------------
    // readOnly
    public func readOnlyHostBuffer() throws -> UnsafeRawBufferPointer {
        try migrate(readOnly: true)
        return UnsafeRawBufferPointer(hostBuffer)
    }
    
    public func readOnlyDevicePointer(using stream: DeviceStream) throws
        -> UnsafeRawPointer {
        try migrate(readOnly: true, using: stream)
        return UnsafeRawPointer(deviceDataPointer)
    }

    //--------------------------------------------------------------------------
    // readWrite
    public func readWriteHostBuffer() throws
        -> UnsafeMutableRawBufferPointer {
        assert(!isReadOnlyReference)
        try migrate(readOnly: false)
        return UnsafeMutableRawBufferPointer(hostBuffer)
    }

    public func readWriteDevicePointer(using stream: DeviceStream) throws ->
        UnsafeMutableRawPointer {
        assert(!isReadOnlyReference)
        try migrate(readOnly: false, using: stream)
        return deviceDataPointer
    }

    //--------------------------------------------------------------------------
    /// migrate
    /// This migrates the master version of the data from wherever it is to
    /// wherever it needs to be
    private func migrate(readOnly: Bool,
                         using stream: DeviceStream? = nil) throws {
        // if the array is empty then there is nothing to do
        guard !isReadOnlyReference && byteCount > 0 else { return }
        let srcUsesUMA = master?.stream.device.memoryAddressing != .discreet
        let dstUsesUMA = stream?.device.memoryAddressing != .discreet

        // reset, this is to support automated tests
        lastAccessCopiedBuffer = false

        if srcUsesUMA {
            if dstUsesUMA {
                try setDeviceDataPointerToHostBuffer(readOnly: readOnly)
            } else {
                assert(stream != nil, streamRequired)
                try host2device(readOnly: readOnly, using: stream!)
            }
        } else {
            if dstUsesUMA {
                try device2host(readOnly: readOnly)
            } else {
                assert(stream != nil, streamRequired)
                try device2device(readOnly: readOnly, using: stream!)
            }
        }
    }

    //--------------------------------------------------------------------------
    // getArray
    // This manages a dictionary of replicated device arrays indexed
    // by serviceId and id. It will lazily create a device array if needed
    private func getArray(for stream: DeviceStream) throws -> ArrayInfo {
        let device = stream.device
        let serviceId = device.service.id

        // add the device array list if needed
        if deviceArrays.count <= serviceId {
            let addCount = max(serviceId + 1, 2) - deviceArrays.count
            for _ in 0..<addCount { deviceArrays.append([ArrayInfo?]()) }
        }

        // create array list if needed
        if deviceArrays[serviceId].isEmpty {
            deviceArrays[serviceId] =
                [ArrayInfo?](repeating: nil,
                             count: device.service.devices.count)
        }

        // return existing if found
        if let info = deviceArrays[serviceId][device.id] {
            // sync the requesting stream with the last stream that accessed it
            try stream.sync(with: info.stream,
                            event: getSyncEvent(using: stream))

            // update the last stream used to access this array for sync
            info.stream = stream
            return info

        } else {
            // create the device array
            diagnostic("\(allocString) \(name)(\(trackingId)) " +
                "device array on \(device.name) elements[\(elementCount)]",
                categories: .dataAlloc)
            
            let array = try device.createArray(count: byteCount)
            array.version = -1
            let info = ArrayInfo(array: array, stream: stream)
            deviceArrays[serviceId][device.id] = info
            return info
        }
    }

    //--------------------------------------------------------------------------
    // createHostArray
    private func createHostArray() throws {
        diagnostic("\(allocString) \(name)(\(trackingId)) " +
            "host array elements[\(elementCount)]", categories: .dataAlloc)
        hostVersion = -1
        hostBuffer = UnsafeMutableRawBufferPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<Double>.alignment)
    }

    //-----------------------------------
    // releaseHostArray
    private func releaseHostArray() {
        assert(!isReadOnlyReference)
        diagnostic("\(releaseString) \(name) TensorArray(\(trackingId)) " +
            "host array elements[\(elementCount)]", categories: .dataAlloc)
        hostBuffer.deallocate()
        hostBuffer = nil
    }

    //--------------------------------------------------------------------------
    // setDeviceDataPointerToHostBuffer
    private func setDeviceDataPointerToHostBuffer(readOnly: Bool) throws {
        assert(!isReadOnlyReference)
        // lazily create the uma buffer if needed
        if hostBuffer == nil { try createHostArray() }
        deviceDataPointer = UnsafeMutableRawPointer(hostBuffer.baseAddress!)
        if !readOnly { master = nil; masterVersion += 1 }
        hostVersion = masterVersion
    }

    //--------------------------------------------------------------------------
    // host2device
    private func host2device(readOnly: Bool,
                             using stream: DeviceStream) throws {
        let arrayInfo = try getArray(for: stream)
        let array     = arrayInfo.array
        deviceDataPointer = array.data

        if hostBuffer == nil {
            // clear the device buffer and set it to be the new master
            try array.zero(using: stream)
            master = arrayInfo

        } else if array.version != masterVersion {
            // copy host data to device if it exists and is needed
            diagnostic("\(copyString) \(name)(\(trackingId)) host" +
                "\(setText(" --> ", color: .blue))" +
                "\(stream.device.name)_s\(stream.id) elements[\(elementCount)]",
                categories: .dataCopy)

            try array.copyAsync(from: UnsafeRawBufferPointer(hostBuffer!),
                                using: stream)
            lastAccessCopiedBuffer = true

            if autoReleaseUmaBuffer && !isReadOnlyReference {
                // wait for the copy to complete, free the uma array,
                // and specify the device array as the new master
                try stream.blockCallerUntilComplete()
                releaseHostArray()
                master = arrayInfo
            }
        }

        // set version
        if !readOnly { master = arrayInfo; masterVersion += 1 }
        array.version = masterVersion
    }

    //--------------------------------------------------------------------------
    // device2host
    private func device2host(readOnly: Bool) throws {
        // master cannot be nil
        let master = self.master!
        assert(master.array.version == masterVersion)

        // lazily create the uma buffer if needed
        if hostBuffer == nil { try createHostArray() }
        deviceDataPointer = UnsafeMutableRawPointer(hostBuffer.baseAddress!)

        // copy if needed
        if hostVersion != masterVersion {
            diagnostic("\(copyString) \(name)(\(trackingId)) " +
                "\(master.stream.device.name)_s\(master.stream.id)" +
                "\(setText(" --> ", color: .blue))host" +
                " elements[\(elementCount)]", categories: .dataCopy)

            // synchronous copy
            try master.array.copy(to: hostBuffer, using: master.stream)
            lastAccessCopiedBuffer = true
        }

        // set version
        if !readOnly { self.master = nil; masterVersion += 1 }
        hostVersion = masterVersion
    }

    //--------------------------------------------------------------------------
    // device2device
    private func device2device(readOnly: Bool,
                               using stream: DeviceStream) throws {
        // master cannot be nil
        let master = self.master!
        assert(master.array.version == masterVersion)

        // get array for stream's device and set deviceBuffer pointer
        let arrayInfo = try getArray(for: stream)
        let array = arrayInfo.array
        deviceDataPointer = array.data

        // synchronize output stream with master stream
        try stream.sync(with: master.stream, event: getSyncEvent(using: stream))

        // copy only if versions do not match
        if array.version != masterVersion {
            // copy within same service
            if master.stream.device.service.id == stream.device.service.id {
                // copy cross device within the same service if needed
                if master.stream.device.id != stream.device.id {
                    diagnostic("\(copyString) \(name)(\(trackingId)) " +
                        "\(master.stream.device.name)" +
                        "\(setText(" --> ", color: .blue))" +
                        "\(stream.device.name)_s\(stream.id) " +
                        "elements[\(elementCount)]",
                        categories: .dataCopy)
                    try array.copyAsync(from: master.array, using: stream)
                    lastAccessCopiedBuffer = true
                }

            } else {
                // cross service
                
                // TODO: test with discreet cpu unit test device and cuda
                fatalError()
                //                if willLog(level: .diagnostic) == true {
                //                    diagnostic("\(copyString) \(name)(\(trackingId)) cross service from " +
                //                        "device(\(master.stream.device.id))" +
                //                    "\(setText(" --> ", color: .blue))" +
                //                        "device(\(stream.device.id)) elementCount: \(elementCount)",
                //                        categories: .dataCopy)
                //                }
                //
                //                // cross service non-uma migration
                //                // copy data to uma buffer
                //                if umaBuffer == nil { try createHostArray() }
                //                try master.array.copy(to: umaBuffer, using: master.stream)
                //
                //                // copy data to destination device
                //                try dest.array.copyAsync(from: BufferUInt8(umaBuffer), using: stream)
                //
                //                if autoReleaseUmaBuffer {
                //                    // wait for the copy to complete, free the uma array,
                //                    // and specify the device array as the new master
                //                    try stream.blockCallerUntilComplete()
                //                    releaseHostArray()
                //                    self.master = dest
                //                }
                //
                //                lastAccessCopiedBuffer = true
            }
        }

        // set version
        if !readOnly { self.master = arrayInfo; masterVersion += 1 }
        self.master!.array.version = masterVersion
        array.version = masterVersion
    }
}
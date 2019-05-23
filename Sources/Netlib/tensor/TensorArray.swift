//******************************************************************************
//  Created by Edward Connell on 3/21/16
//  Copyright © 2016 Connell Research. All rights reserved.
//
import Foundation

//==============================================================================
/// TensorArray
/// The TensorArray object is a flat array of values used by the TensorView.
/// It is responsible for replication and syncing between devices.
/// It is not created or directly used by end users.
final public class TensorArray<Element>: ObjectTracking, Logging {
    //--------------------------------------------------------------------------
    /// used by TensorViews to synchronize access to this object
    public let accessQueue = DispatchQueue(label: "TensorArray.accessQueue")
    /// the number of elements in the data array
    public let count: Int
    /// `true` if the data array references an existing read only buffer
    public let isReadOnly: Bool
    /// testing: `true` if the last access caused the contents of the
    /// buffer to be copied
    public private(set) var lastAccessCopiedBuffer = false
    /// testing: is `true` if the last data access caused the view's underlying
    /// tensorArray object to be copied. It's stored here instead of on the
    /// view, because the view is immutable when taking a read only pointer
    public var lastAccessMutatedView: Bool = false
    /// whenever a buffer write pointer is taken, the associated DeviceArray
    /// becomes the master copy for replication. Synchronization across threads
    /// is still required for taking multiple write pointers, however
    /// this does automatically synchronize data migrations.
    /// The value will be `nil` if no access has been taken yet
    private var master: DeviceArray?
    /// this is incremented each time a write pointer is taken
    /// all replicated buffers will stay in sync with this version
    private var masterVersion = -1
    /// name label used for logging
    public let name: String
    /// replication collection
    private var replicas = [DeviceArrayReplicaKey : DeviceArray]()
    /// the object tracking id
    public private(set) var trackingId = 0
    /// the writeCompletionEvent event is recorded to a stream after a
    /// mutating operation is recorded. Other streams that depend on the
    /// completion of the mutating operation should record the event before
    /// a dependent function is recorded
    public var writeCompletionEvent: StreamEvent?

    //--------------------------------------------------------------------------
    // empty
    public init() {
        count = 0
        isReadOnly = false
        name = ""
    }

    //--------------------------------------------------------------------------
    // casting used for safe conversion between FixedSizeVector and Scalar
    public init<T>(_ other: TensorArray<T>) where
        T: FixedSizeVector, T.Scalar == Element
    {
        self.name = other.name
        self.count = other.count * T.count
        self.replicas = other.replicas
        isReadOnly = false
        register()
        
        diagnostic("\(createString) \(name)(\(trackingId)) " +
            "\(String(describing: Element.self))[\(count)]",
            categories: .dataAlloc)
    }

    //--------------------------------------------------------------------------
    // create a new element array
    public init(count: Int, name: String) {
        self.name = name
        self.count = count
        isReadOnly = false
        register()
        
        diagnostic("\(createString) \(name)(\(trackingId)) " +
            "\(String(describing: Element.self))[\(count)]",
            categories: .dataAlloc)
    }

    //--------------------------------------------------------------------------
    // All initializers copy the data except this one which creates a
    // read only reference to avoid unnecessary copying from the source
    public init(referenceTo buffer: UnsafeBufferPointer<Element>, name: String){
        self.name = name
        self.count = buffer.count
        masterVersion = 0
        isReadOnly = true
        
        // create the replica device array
        let stream = _Streams.current
        let key = stream.device.deviceArrayReplicaKey
        let bytes = UnsafeRawBufferPointer(buffer)
        let array = stream.device.createReferenceArray(buffer: bytes)
        array.version = -1
        replicas[key] = array
        register()

        diagnostic("\(referenceString) \(name)(\(trackingId)) " +
            "readOnly device array reference on \(stream.device.name) " +
            "\(String(describing: Element.self))[\(buffer.count)]",
            categories: .dataAlloc)
    }
    
    //--------------------------------------------------------------------------
    // All initializers retain the data except this one
    // which creates a read only reference to avoid unnecessary copying from
    // a read only data object
    public init(referenceTo buffer: UnsafeMutableBufferPointer<Element>,
                name: String) {
        self.name = name
        self.count = buffer.count
        masterVersion = 0
        isReadOnly = false
        
        // create the replica device array
        let stream = _Streams.current
        let key = stream.device.deviceArrayReplicaKey
        let bytes = UnsafeMutableRawBufferPointer(buffer)
        let array = stream.device.createMutableReferenceArray(buffer: bytes)
        array.version = -1
        replicas[key] = array
        register()

        diagnostic("\(referenceString) \(name)(\(trackingId)) " +
            "readWrite device array reference on \(stream.device.name) " +
            "\(String(describing: Element.self))[\(buffer.count)]",
            categories: .dataAlloc)
    }
    
    //--------------------------------------------------------------------------
    // init from other TensorArray
    public init(copying other: TensorArray, using stream: DeviceStream) throws {
        // initialize members
        isReadOnly = other.isReadOnly
        count = other.count
        name = other.name
        masterVersion = 0
        register()
        
        // report
        diagnostic("\(createString) \(name)(\(trackingId)) init" +
            "\(setText(" copying ", color: .blue))" +
            "TensorArray(\(other.trackingId)) " +
            "\(String(describing: Element.self))[\(count)]",
            categories: [.dataAlloc, .dataCopy])

        // make sure there is something to copy
        guard let otherMaster = other.master else { return }
        
        // get the array replica for `stream`
        let replica = try getArray(for: stream)
        replica.version = masterVersion
        
        // copy the other master array
        try replica.copyAsync(from: otherMaster, using: stream)
        
        // record async copy completion event
        writeCompletionEvent = try stream.record(event: stream.createEvent())

        diagnostic("\(copyString) \(name)(\(trackingId)) " +
            "\(otherMaster.device.name)" +
            "\(setText(" --> ", color: .blue))" +
            "\(stream.device.name)_s\(stream.id) " +
            "\(String(describing: Element.self))[\(count)]",
            categories: .dataCopy)
    }

    //--------------------------------------------------------------------------
    // object lifetime tracking for leak detection
    private func register() {
        trackingId = ObjectTracker.global
            .register(self, namePath: logNamePath, supplementalInfo:
                "\(String(describing: Element.self))[\(count)]")
    }
    
    //--------------------------------------------------------------------------
    deinit {
        // make sure any pending write operations are complete
        writeCompletionEvent?.wait()
        ObjectTracker.global.remove(trackingId: trackingId)

        if count > 0 {
            diagnostic("\(releaseString) \(name)(\(trackingId)) ",
                categories: .dataAlloc)
        }
    }

    //--------------------------------------------------------------------------
    /// readOnly
    /// - Parameter type: the cast Element type of the buffer returned
    /// - Parameter stream: the stream to use
    /// - Returns: an Element buffer of type T
    public func readOnly<T>(type: T.Type, using stream: DeviceStream) throws
        -> UnsafeBufferPointer<T>
    {
        let buffer = try migrate(readOnly: true, using: stream)
        return buffer.withMemoryRebound(to: T.self) { UnsafeBufferPointer($0) }
    }
    
    //--------------------------------------------------------------------------
    /// readWrite
    public func readWrite<T>(type: T.Type, using stream: DeviceStream) throws ->
        UnsafeMutableBufferPointer<T>
    {
        assert(!isReadOnly, "the TensorArray is read only")
        let buffer = try migrate(readOnly: false, using: stream)
        return buffer.withMemoryRebound(to: T.self) { $0 }
    }
    
    //--------------------------------------------------------------------------
    /// migrate
    /// This migrates the master version of the data from wherever it is to
    /// the device associated with `stream` and returns a pointer to the data
    private func migrate(readOnly: Bool, using stream: DeviceStream) throws
        -> UnsafeMutableBufferPointer<Element>
    {
        // get the array replica for `stream`
        let replica = try getArray(for: stream)
        lastAccessCopiedBuffer = false

        // compare with master and copy if needed
        if let master = master, replica.version != master.version {
            // cross service?
            if replica.device.service.id != master.device.service.id {
                try copyCrossService(from: master, to: replica, using: stream)
                
            } else if replica.device.id != master.device.id {
                try copyCrossDevice(from: master, to: replica, using: stream)
            }
        }
        
        // set version
        if !readOnly { master = replica; masterVersion += 1 }
        replica.version = masterVersion
        return replica.buffer.bindMemory(to: Element.self)
    }

    //--------------------------------------------------------------------------
    // copyCrossService
    // copies from an array in one service to another
    private func copyCrossService(from master: DeviceArray,
                                  to other: DeviceArray,
                                  using stream: DeviceStream) throws
    {
        lastAccessCopiedBuffer = true
        
        if master.device.memoryAddressing == .unified {
            // copy host to discreet memory device
            if other.device.memoryAddressing == .discreet {
                // get the master uma buffer
                let buffer = UnsafeRawBufferPointer(master.buffer)
                try other.copyAsync(from: buffer, using: stream)

                diagnostic("\(copyString) \(name)(\(trackingId)) " +
                    "uma:\(master.device.name)" +
                    "\(setText(" --> ", color: .blue))" +
                    "\(other.device.name)_s\(stream.id) " +
                    "\(String(describing: Element.self))" +
                    "[\(master.buffer.bindMemory(to: Element.self).count)]",
                    categories: .dataCopy)
            }
            // otherwise they are both unified, so do nothing
        } else if other.device.memoryAddressing == .unified {
            // device to host
            try master.copyAsync(to: other.buffer, using: stream)
            
            diagnostic("\(copyString) \(name)(\(trackingId)) " +
                "\(master.device.name)_s\(stream.id)" +
                "\(setText(" --> ", color: .blue))uma:\(other.device.name) " +
                "\(String(describing: Element.self))" +
                "[\(master.buffer.bindMemory(to: Element.self).count)]",
                categories: .dataCopy)

        } else {
            // both are discreet and not in the same service, so
            // transfer to host memory as an intermediate step
            let host = try getArray(for: _Streams.hostStream)
            try master.copyAsync(to: host.buffer, using: stream)
            
            diagnostic("\(copyString) \(name)(\(trackingId)) " +
                "\(master.device.name)_s\(stream.id)" +
                "\(setText(" --> ", color: .blue))\(other.device.name)" +
                "\(String(describing: Element.self))[\(count)]",
                categories: .dataCopy)
            
            let hostBuffer = UnsafeRawBufferPointer(host.buffer)
            try other.copyAsync(from: hostBuffer, using: stream)
            
            diagnostic("\(copyString) \(name)(\(trackingId)) " +
                "\(other.device.name)" +
                "\(setText(" --> ", color: .blue))" +
                "\(master.device.name)_s\(stream.id) " +
                "\(String(describing: Element.self))" +
                "[\(other.buffer.bindMemory(to: Element.self).count)]",
                categories: .dataCopy)
        }
        
        // record async copy completion event
        writeCompletionEvent = try stream.record(event: stream.createEvent())
    }
    
    //--------------------------------------------------------------------------
    // copyCrossDevice
    // copies from one discreet memory device to the other
    private func copyCrossDevice(from master: DeviceArray,
                                 to other: DeviceArray,
                                 using stream: DeviceStream) throws
    {
        // only copy if the devices have discreet memory
        guard master.device.memoryAddressing == .discreet else { return }
        lastAccessCopiedBuffer = true
        
        // async copy and record completion event
        try other.copyAsync(from: master, using: stream)
        writeCompletionEvent = try stream.record(event: stream.createEvent())

        diagnostic("\(copyString) \(name)(\(trackingId)) " +
            "\(master.device.name)" +
            "\(setText(" --> ", color: .blue))" +
            "\(stream.device.name)_s\(stream.id) " +
            "\(String(describing: Element.self))" +
            "[\(master.buffer.bindMemory(to: Element.self).count)]",
            categories: .dataCopy)
    }
    
    //--------------------------------------------------------------------------
    // getArray(stream:
    // This manages a dictionary of replicated device arrays indexed
    // by serviceId and id. It will lazily create a device array if needed
    private func getArray(for stream: DeviceStream) throws -> DeviceArray {
        // lookup array associated with this stream
        let key = stream.device.deviceArrayReplicaKey
        if let replica = replicas[key] {
            return replica
        } else {
            // create the replica device array
            let byteCount = MemoryLayout<Element>.size * count
            let array = try stream.device.createArray(count: byteCount)
            diagnostic("\(allocString) \(name)(\(trackingId)) " +
                "device array on \(stream.device.name) " +
                "\(String(describing: Element.self))" +
                "[\(array.buffer.bindMemory(to: Element.self).count)]",
                categories: .dataAlloc)
            
            array.version = -1
            replicas[key] = array
            return array
        }
    }
}

extension TensorArray: Codable where Element: Codable {
    enum CodingKeys: String, CodingKey { case name, data }

    /// encodes the contents of the array
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        // TODO: we create an Array from the buffer assuming it will take
        // a reference and not copy the data
        let buffer = try readOnly(type: Element.self, using: _Streams.hostStream)
        try container.encode(ContiguousArray(buffer), forKey: .data)
    }
    
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        var data = try container.decode(ContiguousArray<Element>.self,
                                        forKey: .data)
        // TODO: make sure this is safe for ref counting
        let buffer = data.withUnsafeMutableBufferPointer { $0 }
        self.init(referenceTo: buffer, name: name)
    }
}

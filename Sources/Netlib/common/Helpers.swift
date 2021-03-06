//******************************************************************************
//  Created by Edward Connell on 3/30/16
//  Copyright © 2016 Connell Research. All rights reserved.
//
import Foundation

public func NotImplemented() {
    fatalError("not implemented yet")
}

//==============================================================================
// Memory sizes
extension Int {
    var KB: Int { return self * 1024 }
    var MB: Int { return self * 1024 * 1024 }
    var GB: Int { return self * 1024 * 1024 * 1024 }
    var TB: Int { return self * 1024 * 1024 * 1024 * 1024 }
}

//==============================================================================
// String(timeInterval:
extension String {
    public init(timeInterval: TimeInterval) {
        let milliseconds = Int(timeInterval.truncatingRemainder(dividingBy: 1.0) * 1000)
        let interval = Int(timeInterval)
        let seconds = interval % 60
        let minutes = (interval / 60) % 60
        let hours = (interval / 3600)
        self = String(format: "%0.2d:%0.2d:%0.2d.%0.3d",
                      hours, minutes, seconds, milliseconds)
    }
}

//==============================================================================
// almostEquals
public func almostEquals<T: AnyNumeric>(_ a: T, _ b: T,
                                       tolerance: Double = 0.00001) -> Bool {
    return abs(a.asDouble - b.asDouble) < tolerance
}

//==============================================================================
// AtomicCounter
public final class AtomicCounter {
    // properties
    private var counter: Int
    private let mutex = Mutex()
    
    public var value: Int {
        get { return mutex.sync { counter } }
        set { return mutex.sync { counter = newValue } }
    }
    
    // initializers
    public init(value: Int = 0) {
        counter = value
    }
    
    // functions
    public func increment() -> Int {
        return mutex.sync {
            counter += 1
            return counter
        }
    }
}

//==============================================================================
// Mutex
public final class Mutex {
    // properties
    private let semaphore = DispatchSemaphore(value: 1)
    
    // functions
    func sync<R>(execute work: () throws -> R) rethrows -> R {
        semaphore.wait()
        defer { semaphore.signal() }
        return try work()
    }
}

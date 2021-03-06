//******************************************************************************
//  Created by Edward Connell on 5/3/19
//  Copyright © 2019 Connell Research. All rights reserved.
//

/// `Zip3Sequence` iterator
public struct Zip3Iterator<I1, I2, I3> where
I1: IteratorProtocol, I2: IteratorProtocol, I3: IteratorProtocol {
    var _I1: I1
    var _I2: I2
    var _I3: I3
    
    init(_ I1: I1, _ I2: I2, _ I3: I3) {
        self._I1 = I1
        self._I2 = I2
        self._I3 = I3
    }
}

extension Zip3Iterator: IteratorProtocol {
    public typealias Element = (I1.Element, I2.Element, I3.Element)
    
    public mutating func next() -> Zip3Iterator.Element? {
        guard let next1 = _I1.next(),
            let next2 = _I2.next(),
            let next3 = _I3.next() else {
                return nil
        }
        return (next1, next2, next3)
    }
}

public struct Zip3Sequence<S1, S2, S3> where
S1: Sequence, S2: Sequence, S3: Sequence {
    let _s1: S1
    let _s2: S2
    let _s3: S3
    
    init(_ s1: S1, _ s2: S2, _ s3: S3) {
        self._s1 = s1
        self._s2 = s2
        self._s3 = s3
    }
}

extension Zip3Sequence : Sequence {
    public typealias Iterator = Zip3Iterator<S1.Iterator, S2.Iterator, S3.Iterator>
    
    public func makeIterator() -> Zip3Sequence.Iterator {
        return Zip3Iterator.init(_s1.makeIterator(), _s2.makeIterator(),
                                 _s3.makeIterator())
    }
}

public func zip<S1, S2, S3>(_ s1: S1, _ s2: S2, _ s3: S3) ->
    Zip3Sequence<S1, S2, S3> where S1 : Sequence, S2 : Sequence, S3: Sequence {
    return Zip3Sequence(s1, s2, s3)
}

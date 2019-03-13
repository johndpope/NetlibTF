//******************************************************************************
//  Created by Edward Connell on 3/3/19.
//  Copyright © 2019 Edward Connell. All rights reserved.
//
import Foundation

public struct TensorShape : Equatable {
    //--------------------------------------------------------------------------
    // properties
    /// The extent of the shape in each dimension
    public let dimensions: [Int]
    /// The dense number of elements defined by the shape
    public let elementCount: Int
    /// The sparse number of elements spanned by the shape
    public let elementSpanCount: Int
    /// The interpretation of each dimension in the shape
    public let layout: TensorLayout
    /// The distance to the next element for each dimension
    public let strides: [Int]

    // convenience shorthand
    public var isContiguous: Bool { return elementCount == elementSpanCount }
    public var isEmpty: Bool { return elementCount == 0 }
    public var isScalar: Bool { return layout == .scalar }
    public var rank: Int { return dimensions.count }

    public var items: Int { return dimensions[layout.nAxis] }
    public var channels: Int { return dimensions[layout.cAxis] }
    public var depths: Int { return dimensions[layout.dAxis] }
    public var rows: Int { return dimensions[layout.hAxis] }
    public var cols: Int { return dimensions[layout.wAxis] }

    public var itemStride: Int { return strides[layout.nAxis] }
    public var channelStride: Int { return strides[layout.cAxis] }
    public var depthStride: Int { return strides[layout.dAxis] }
    public var rowStride: Int { return strides[layout.hAxis] }
    public var colStride: Int { return strides[layout.wAxis] }

    //--------------------------------------------------------------------------
    /// Initialize with all options
    /// - Parameter dimensions: extent of the shape in each dimension
    /// - Parameter layout: defines the interpretation of each dimension
    /// - Parameter strides: the distance to the next element in each dimension
    /// - Parameter colMajor: if `true` it allows normal indexing of imported
    ///             row major data, such as matrices from Matlab or Octave
    public init(dimensions: [Int],
                layout: TensorLayout? = nil,
                strides: [Int]? = nil,
                colMajor: Bool = false) {
        // validate and assign
        assert(strides == nil || strides?.count == dimensions.count)
        let rank = dimensions.count
        self.dimensions = dimensions
        self.elementCount = dimensions.reduce(1, *)
        self.layout = layout ?? TensorLayout(defaultForRank: rank)

        // strides
        if let userStrides = strides {
            self.strides = userStrides
        } else if colMajor {
            var cmExtent = dimensions
            cmExtent.swapAt(self.layout.hAxis, self.layout.wAxis)
            var cmStrides = TensorShape.denseStrides(for: cmExtent)
            cmStrides.swapAt(self.layout.hAxis, self.layout.wAxis)
            self.strides = cmStrides
        } else {
            self.strides = TensorShape.denseStrides(for: dimensions)
        }
        elementSpanCount = TensorShape.spanCount(for: dimensions,
                                                 with: self.strides)
    }
    
    /// Initialize with an array literal representing the shape dimensions.
    /// The rank of the tensor is the number of dimensions.
    /// - Parameter elements: The shape dimensions.
    @inlinable @inline(__always)
    public init(arrayLiteral elements: Int...) {
        self.init(dimensions: elements)
    }
    
    /// Initialize with variadic elements representing the shape dimensions.
    /// The rank of the tensor is the number of elements.
    /// - Parameter elements: The shape dimensions.
    @inlinable @inline(__always)
    public init(_ elements: Int...) {
        self.init(dimensions: elements)
    }
    
    /// Initialize with an array representing the shape dimensions.
    /// The rank of the tensor is the number of elements.
    /// - Parameter elements: The shape dimensions.
    @inlinable @inline(__always)
    public init(_ elements: [Int]) {
        self.init(dimensions: elements)
    }
    
    //--------------------------------------------------------------------------
    // denseStrides
    private static func denseStrides(for dimensions: [Int]) -> [Int] {
        var strides = [Int](repeating: 1, count: dimensions.count)
        for i in (1..<dimensions.count).reversed() {
            strides[i-1] = dimensions[i] * strides[i]
        }
        return strides
    }
    
    //--------------------------------------------------------------------------
    // spanCount
    // A sub view may cover a wider range of parent element indexes
    // than the number of elements defined by the extent of this view
    // The span of the extent is the linear index of the last index + 1
    private static func spanCount(for dimensions: [Int],
                                  with strides: [Int]) -> Int {
        return zip(dimensions, strides).reduce(0) { $0 + ($1.0 - 1) * $1.1 } + 1
    }
}

//==============================================================================
// TensorLayout
public enum TensorLayout : Int {
    // warning: don't rearrange without also updating axis mapping below
    case scalar, vector, matrix, volume, nchw, nhwc, ncdhw, ndhwc
    
    // axis mapping                 s  ve m  vo nc nh nc nd
    public var nAxis: Int { return [0, 0, 0, 0, 0, 0, 0, 0][rawValue] }
    public var cAxis: Int { return [0, 0, 0, 0, 1, 3, 1, 4][rawValue] }
    public var dAxis: Int { return [0, 0, 0, 0, 0, 0, 2, 1][rawValue] }
    public var hAxis: Int { return [0, 0, 0, 1, 2, 1, 3, 2][rawValue] }
    public var wAxis: Int { return [0, 0, 1, 2, 3, 2, 4, 3][rawValue] }

    public init(defaultForRank rank: Int) {
        self = [.scalar, .vector, .matrix, .volume, .nchw, .ncdhw][rank]
    }
}
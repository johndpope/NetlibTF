//******************************************************************************
//  Created by Edward Connell on 3/30/19
//  Copyright © 2019 Edward Connell. All rights reserved.
//
import Foundation

//==============================================================================
/// conformance indicates that scalar components are of the same type and
/// densely packed. This is necessary for zero copy view type casting of
/// non numeric scalar types.
/// For example: Matrix<RGBASample<Float>> -> NHWCTensor<Float>
///
public protocol UniformDenseScalar: Equatable {
    associatedtype Component: AnyFixedSizeScalar
    static var componentCount: Int { get }
}

public extension UniformDenseScalar {
    static var componentCount: Int {
        return MemoryLayout<Self>.size / MemoryLayout<Component>.size
    }
}

//==============================================================================
// Image Scalar types
public protocol RGBImageSample: UniformDenseScalar, DefaultInitializer {
    var r: Component { get set }
    var g: Component { get set }
    var b: Component { get set }
}

public struct RGBSample<Component>: RGBImageSample
where Component: AnyNumeric & AnyFixedSizeScalar {
    public var r, g, b: Component
    public init() { r = Component.zero; g = Component.zero; b = Component.zero }
}

public protocol RGBAImageSample: UniformDenseScalar, DefaultInitializer {
    var r: Component { get set }
    var g: Component { get set }
    var b: Component { get set }
    var a: Component { get set }
}

public struct RGBASample<Component> : RGBAImageSample
where Component: AnyNumeric & AnyFixedSizeScalar {
    public var r, g, b, a: Component
    public init() {
        r = Component.zero
        g = Component.zero
        b = Component.zero
        a = Component.zero
    }
}

//==============================================================================
// Audio sample types
public protocol StereoAudioSample: UniformDenseScalar, DefaultInitializer {
    var left: Component { get set }
    var right: Component { get set }
}

public struct StereoSample<Component>: StereoAudioSample
where Component: AnyNumeric & AnyFixedSizeScalar {
    public var left, right: Component
    public init() { left = Component.zero; right = Component.zero }
}

//==============================================================================
// ScalarTensorView
public protocol ScalarView: TensorView where
    BoolView == ScalarValue<Bool>,
    IndexView == ScalarValue<IndexScalar>{}

public extension ScalarView {
    //--------------------------------------------------------------------------
    /// shaped initializers
    init(_ value: Scalar,
         padding: [Padding]? = nil, padValue: Scalar? = nil,
         name: String? = nil) {
        
        let shape = DataShape(extents: [1])
        self.init(shape: shape, dataShape: shape, name: name,
                  padding: padding, padValue: padValue,
                  tensorData: nil, viewDataOffset: 0,
                  isShared: false, scalars: nil)
    }
}

//------------------------------------------------------------------------------
// ScalarValue
public struct ScalarValue<Scalar>: ScalarView
where Scalar: ScalarConformance {
    // properties
    public let dataShape: DataShape
    public let isShared: Bool
    public let isVirtual: Bool
    public let padding: [Padding]
    public let padValue: Scalar
    public let shape: DataShape
    public var tensorData: TensorData!
    public var viewDataOffset: Int
    
    public init(shape: DataShape,
                dataShape: DataShape,
                name: String?,
                padding: [Padding]?,
                padValue: Scalar?,
                tensorData: TensorData?,
                viewDataOffset: Int,
                isShared: Bool,
                scalars: [Scalar]?) {
        self.shape = shape
        self.dataShape = dataShape
        self.padding = padding ?? [Padding(0)]
        self.padValue = padValue ?? Scalar()
        self.isShared = isShared
        self.isVirtual = padding != nil || dataShape != shape
        self.viewDataOffset = viewDataOffset
        self.tensorData = tensorData ?? initTensorData(name, scalars)
    }
}

extension ScalarValue: CustomStringConvertible where Scalar: AnyConvertable {
    public var description: String { return formatted() }
}

//==============================================================================
// VectorView
public protocol VectorView: TensorView
where BoolView == Vector<Bool>, IndexView == Vector<IndexScalar> { }

public extension VectorView {
    //--------------------------------------------------------------------------
    /// shaped initializers

    /// with Array
    init(count: Int, name: String? = nil,
         padding: [Padding]? = nil, padValue: Scalar? = nil) {
        
        let shape = DataShape(extents: [count])
        self.init(shape: shape, dataShape: shape, name: name,
                  padding: padding, padValue: padValue,
                  tensorData: nil, viewDataOffset: 0,
                  isShared: false, scalars: nil)
    }
    
    /// with Sequence
    init<Seq>(count: Int, name: String? = nil,
              padding: [Padding]? = nil, padValue: Scalar? = nil,
              isColMajor: Bool = false, sequence: Seq) where
        Seq: Sequence, Seq.Element: AnyConvertable,
        Scalar: AnyConvertable
    {
        self.init(name: name,
                  padding: padding, padValue: padValue,
                  scalars: Self.sequence2ScalarArray(sequence))
    }

    //-------------------------------------
    /// with reference to read only buffer
    /// useful for memory mapped databases, or hardware device buffers
    init(name: String? = nil,
         padding: [Padding]? = nil, padValue: Scalar? = nil,
         readOnlyReferenceTo buffer: UnsafeRawBufferPointer) {
        
        // create tensor data reference to buffer
        let tensorData = TensorData(readOnlyReferenceTo: buffer,
                                    name: name ?? String(describing: Self.self))
        
        // create shape considering column major
        let shape = DataShape(extents: [buffer.count])
        self.init(shape: shape, dataShape: shape, name: name,
                  padding: padding, padValue: padValue,
                  tensorData: tensorData, viewDataOffset: 0,
                  isShared: false, scalars: nil)
    }

    //--------------------------------------------------------------------------
    /// initialize with scalar array
    init(name: String? = nil,
         padding: [Padding]? = nil, padValue: Scalar? = nil,
         scalars: [Scalar]) {
        let shape = DataShape(extents: [scalars.count])
        self.init(shape: shape, dataShape: shape, name: name,
                  padding: padding, padValue: padValue,
                  tensorData: nil, viewDataOffset: 0,
                  isShared: false, scalars: scalars)
    }

    /// with Sequence
    init<Seq>(name: String? = nil,
              padding: [Padding]? = nil, padValue: Scalar? = nil,
              sequence: Seq) where
        Seq: Sequence, Seq.Element: AnyConvertable,
        Scalar: AnyConvertable
    {
        let scalars = Self.sequence2ScalarArray(sequence)
        let shape = DataShape(extents: [scalars.count])
        self.init(shape: shape, dataShape: shape, name: name,
                  padding: padding, padValue: padValue,
                  tensorData: nil, viewDataOffset: 0,
                  isShared: false, scalars: scalars)
    }
}

//------------------------------------------------------------------------------
// Vector
public struct Vector<Scalar>: VectorView
where Scalar: ScalarConformance {
    // properties
    public let dataShape: DataShape
    public let isShared: Bool
    public let isVirtual: Bool
    public let padding: [Padding]
    public let padValue: Scalar
    public let shape: DataShape
    public var tensorData: TensorData!
    public var viewDataOffset: Int
    
    public init(shape: DataShape,
                dataShape: DataShape,
                name: String?,
                padding: [Padding]?,
                padValue: Scalar?,
                tensorData: TensorData?,
                viewDataOffset: Int,
                isShared: Bool,
                scalars: [Scalar]?) {
        self.shape = shape
        self.dataShape = dataShape
        self.padding = padding ?? [Padding(0)]
        self.padValue = padValue ?? Scalar()
        self.isShared = isShared
        self.isVirtual = padding != nil || dataShape != shape
        self.viewDataOffset = viewDataOffset
        self.tensorData = tensorData ?? initTensorData(name, scalars)
    }
}

extension Vector: CustomStringConvertible where Scalar: AnyConvertable {
    public var description: String { return formatted() }
}

//==============================================================================
// MatrixView
public protocol MatrixView: TensorView
where BoolView == Matrix<Bool>, IndexView == Matrix<IndexScalar> {}

public extension MatrixView {
    var rowCount: Int { return shape.extents[0] }
    var colCount: Int { return shape.extents[1] }
    
    //--------------------------------------------------------------------------
    /// shaped initializers

    //-------------------------------------
    /// with Array
    init(extents: [Int], name: String? = nil,
         padding: [Padding]? = nil, padValue: Scalar? = nil,
         isColMajor: Bool = false, scalars: [Scalar]? = nil) {
        
        let shape = !isColMajor ? DataShape(extents: extents) :
            DataShape(extents: extents).columnMajor()
        
        self.init(shape: shape, dataShape: shape, name: name,
                  padding: padding, padValue: padValue,
                  tensorData: nil, viewDataOffset: 0,
                  isShared: false, scalars: scalars)
    }
    
    //-------------------------------------
    /// with Sequence
    init<Seq>(extents: [Int], name: String? = nil,
              padding: [Padding]? = nil, padValue: Scalar? = nil,
              isColMajor: Bool = false, sequence: Seq) where
        Seq: Sequence, Seq.Element: AnyConvertable,
        Scalar: AnyConvertable
    {
        self.init(extents: extents, name: name,
                  padding: padding, padValue: padValue,
                  isColMajor: isColMajor,
                  scalars: Self.sequence2ScalarArray(sequence))
    }

    //-------------------------------------
    /// with reference to read only buffer
    /// useful for memory mapped databases, or hardware device buffers
    init(extents: [Int], name: String? = nil,
         padding: [Padding]? = nil, padValue: Scalar? = nil,
         isColMajor: Bool = false,
         readOnlyReferenceTo buffer: UnsafeRawBufferPointer) {
        
        // create tensor data reference to buffer
        let tensorData = TensorData(readOnlyReferenceTo: buffer,
                                    name: name ?? String(describing: Self.self))
        
        // create shape considering column major
        let shape = !isColMajor ? DataShape(extents: extents) :
            DataShape(extents: extents).columnMajor()
        assert(shape.elementCount == buffer.count,
               "shape count does not match buffer count")
        
        self.init(shape: shape, dataShape: shape, name: name,
                  padding: padding, padValue: padValue,
                  tensorData: tensorData, viewDataOffset: 0,
                  isShared: false, scalars: nil)
    }

    //--------------------------------------------------------------------------
    /// initialize with explicit labels
    init(_ rows: Int, _ cols: Int, name: String? = nil,
         padding: [Padding]? = nil, padValue: Scalar? = nil,
         isColMajor: Bool = false, scalars: [Scalar]? = nil) {
        
        self.init(extents: [rows, cols], name: name,
                  padding: padding, padValue: padValue,
                  isColMajor: isColMajor, scalars: scalars)
    }

    //-------------------------------------
    init<Seq>(_ rows: Int, _ cols: Int, name: String? = nil,
              padding: [Padding]? = nil, padValue: Scalar? = nil,
              isColMajor: Bool = false, sequence: Seq) where
        Seq: Sequence, Seq.Element: AnyConvertable,
        Scalar: AnyConvertable
    {
        self.init(extents: [rows, cols], name: name,
                  padding: padding, padValue: padValue,
                  isColMajor: isColMajor,
                  scalars: Self.sequence2ScalarArray(sequence))
    }
}

//------------------------------------------------------------------------------
// Matrix
public struct Matrix<Scalar>: MatrixView
where Scalar: ScalarConformance {
    // properties
    public let dataShape: DataShape
    public let isShared: Bool
    public let isVirtual: Bool
    public let padding: [Padding]
    public let padValue: Scalar
    public let shape: DataShape
    public var tensorData: TensorData!
    public var viewDataOffset: Int
    
    public init(shape: DataShape,
                dataShape: DataShape,
                name: String?,
                padding: [Padding]?,
                padValue: Scalar?,
                tensorData: TensorData?,
                viewDataOffset: Int,
                isShared: Bool,
                scalars: [Scalar]?) {
        self.shape = shape
        self.dataShape = dataShape
        self.padding = padding ?? [Padding(0)]
        self.padValue = padValue ?? Scalar()
        self.isShared = isShared
        self.isVirtual = padding != nil || dataShape != shape
        self.viewDataOffset = viewDataOffset
        self.tensorData = tensorData ?? initTensorData(name, scalars)
    }
}

extension Matrix: CustomStringConvertible where Scalar: AnyConvertable {
    public var description: String { return formatted() }
}

//==============================================================================
// VolumeView
public protocol VolumeView: TensorView
where BoolView == Volume<Bool>, IndexView == Volume<IndexScalar> { }

public extension VolumeView {
    //--------------------------------------------------------------------------
    /// shaped initializers
    
    //-------------------------------------
    /// with Array
    init(extents: [Int], name: String? = nil,
         padding: [Padding]? = nil, padValue: Scalar? = nil,
         scalars: [Scalar]? = nil) {
        
        let shape = DataShape(extents: extents)
        self.init(shape: shape, dataShape: shape, name: name,
                  padding: padding, padValue: padValue,
                  tensorData: nil, viewDataOffset: 0,
                  isShared: false, scalars: scalars)
    }
    
    //-------------------------------------
    /// with Sequence
    init<Seq>(extents: [Int], name: String? = nil,
              padding: [Padding]? = nil, padValue: Scalar? = nil,
              sequence: Seq) where
        Seq: Sequence, Seq.Element: AnyConvertable,
        Scalar: AnyConvertable
    {
        self.init(extents: extents, name: name,
                  padding: padding, padValue: padValue,
                  scalars: Self.sequence2ScalarArray(sequence))
    }
    
    //-------------------------------------
    /// with reference to read only buffer
    /// useful for memory mapped databases, or hardware device buffers
    init(extents: [Int], name: String? = nil,
         padding: [Padding]? = nil, padValue: Scalar? = nil,
         readOnlyReferenceTo buffer: UnsafeRawBufferPointer) {
        
        // create tensor data reference to buffer
        let tensorData = TensorData(readOnlyReferenceTo: buffer,
                                    name: name ?? String(describing: Self.self))
        
        // create shape considering column major
        let shape = DataShape(extents: extents)
        assert(shape.elementCount == buffer.count,
               "shape count does not match buffer count")
        
        self.init(shape: shape, dataShape: shape, name: name,
                  padding: padding, padValue: padValue,
                  tensorData: tensorData, viewDataOffset: 0,
                  isShared: false, scalars: nil)
    }
    
    //--------------------------------------------------------------------------
    /// initialize with explicit labels
    init(_ depths: Int, _ rows: Int, _ cols: Int,
         padding: [Padding]? = nil, padValue: Scalar? = nil,
         name: String? = nil, scalars: [Scalar]? = nil) {
        
        self.init(extents: [depths, rows, cols], name: name,
                  padding: padding, padValue: padValue,
                  scalars: scalars)
    }
    
    //-------------------------------------
    init<Seq>(_ depths: Int, _ rows: Int, _ cols: Int, name: String? = nil,
              padding: [Padding]? = nil, padValue: Scalar? = nil,
              isColMajor: Bool = false, sequence: Seq) where
        Seq: Sequence, Seq.Element: AnyConvertable,
        Scalar: AnyConvertable
    {
        self.init(extents: [depths, rows, cols], name: name,
                  padding: padding, padValue: padValue,
                  scalars: Self.sequence2ScalarArray(sequence))
    }
}

//------------------------------------------------------------------------------
/// Volume
public struct Volume<Scalar>: VolumeView
where Scalar: ScalarConformance {
    // properties
    public let dataShape: DataShape
    public let isShared: Bool
    public let isVirtual: Bool
    public let padding: [Padding]
    public let padValue: Scalar
    public let shape: DataShape
    public var tensorData: TensorData!
    public var viewDataOffset: Int
    
    public init(shape: DataShape,
                dataShape: DataShape,
                name: String?,
                padding: [Padding]?,
                padValue: Scalar?,
                tensorData: TensorData?,
                viewDataOffset: Int,
                isShared: Bool,
                scalars: [Scalar]?) {
        self.shape = shape
        self.dataShape = dataShape
        self.padding = padding ?? [Padding(0)]
        self.padValue = padValue ?? Scalar()
        self.isShared = isShared
        self.isVirtual = padding != nil || dataShape != shape
        self.viewDataOffset = viewDataOffset
        self.tensorData = tensorData ?? initTensorData(name, scalars)
    }
}

extension Volume: CustomStringConvertible where Scalar: AnyConvertable {
    public var description: String { return formatted() }
}

//==============================================================================
// NDTensorView
public protocol NDTensorView: TensorView
where BoolView == NDTensor<Bool>, IndexView == NDTensor<IndexScalar> { }

public extension NDTensorView {
    //-------------------------------------
    /// with reference to read only buffer
    /// useful for memory mapped databases, or hardware device buffers
    init(extents: [Int], name: String? = nil,
         padding: [Padding]? = nil, padValue: Scalar? = nil,
         readOnlyReferenceTo buffer: UnsafeRawBufferPointer) {
        
        // create tensor data reference to buffer
        let tensorData = TensorData(readOnlyReferenceTo: buffer,
                                    name: name ?? String(describing: Self.self))
        
        // create shape considering column major
        let shape = DataShape(extents: extents)
        assert(shape.elementCount == buffer.count,
               "shape count does not match buffer count")
        
        self.init(shape: shape, dataShape: shape, name: name,
                  padding: padding, padValue: padValue,
                  tensorData: tensorData, viewDataOffset: 0,
                  isShared: false, scalars: nil)
    }
    
    //-------------------------------------
    /// with Sequence
    init<Seq>(extents: [Int], name: String? = nil,
              padding: [Padding]? = nil, padValue: Scalar? = nil,
              sequence: Seq) where
        Seq: Sequence, Seq.Element: AnyConvertable,
        Scalar: AnyConvertable
    {
        let shape = DataShape(extents: extents)
        self.init(shape: shape, dataShape: shape, name: name,
                  padding: padding, padValue: padValue,
                  tensorData: nil, viewDataOffset: 0,
                  isShared: false,
                  scalars: Self.sequence2ScalarArray(sequence))
    }
}

//------------------------------------------------------------------------------
// NDTensor
// This is an n-dimentional tensor without specialized extent accessors
public struct NDTensor<Scalar>: NDTensorView
where Scalar: ScalarConformance {
    // properties
    public let dataShape: DataShape
    public let isShared: Bool
    public let isVirtual: Bool
    public let padding: [Padding]
    public let padValue: Scalar
    public let shape: DataShape
    public var tensorData: TensorData!
    public var viewDataOffset: Int
    
    public init(shape: DataShape,
                dataShape: DataShape,
                name: String?,
                padding: [Padding]?,
                padValue: Scalar?,
                tensorData: TensorData?,
                viewDataOffset: Int,
                isShared: Bool,
                scalars: [Scalar]?) {
        self.shape = shape
        self.dataShape = dataShape
        self.padding = padding ?? [Padding(0)]
        self.padValue = padValue ?? Scalar()
        self.isShared = isShared
        self.isVirtual = padding != nil || dataShape != shape
        self.viewDataOffset = viewDataOffset
        self.tensorData = tensorData ?? initTensorData(name, scalars)
    }
}

extension NDTensor: CustomStringConvertible where Scalar: AnyConvertable {
    public var description: String { return formatted() }
}

//==============================================================================
/// NCHWTensorView
/// An NCHW tensor is a standard layout for use with cuDNN.
/// It has a layout of numerics organized as:
/// n: items
/// c: channels
/// h: rows
/// w: cols
public protocol NCHWTensorView: TensorView
where BoolView == NCHWTensor<Bool>, IndexView == NCHWTensor<IndexScalar> { }

public extension NCHWTensorView {
    //--------------------------------------------------------------------------
    /// shaped initializers
    
    //-------------------------------------
    /// with Array
    init(extents: [Int], name: String? = nil,
         padding: [Padding]? = nil, padValue: Scalar? = nil,
         scalars: [Scalar]? = nil) {

        let shape = DataShape(extents: extents)
        self.init(shape: shape, dataShape: shape, name: name,
                  padding: padding, padValue: padValue,
                  tensorData: nil, viewDataOffset: 0,
                  isShared: false, scalars: scalars)
    }
    
    //-------------------------------------
    /// with Sequence
    init<Seq>(extents: [Int], name: String? = nil,
              padding: [Padding]? = nil, padValue: Scalar? = nil,
              isColMajor: Bool = false, sequence: Seq) where
        Seq: Sequence, Seq.Element: AnyConvertable,
        Scalar: AnyConvertable
    {
        self.init(extents: extents, name: name,
                  padding: padding, padValue: padValue,
                  scalars: Self.sequence2ScalarArray(sequence))
    }

    //-------------------------------------
    /// with reference to read only buffer
    /// useful for memory mapped databases, or hardware device buffers
    init(extents: [Int], name: String? = nil,
         padding: [Padding]? = nil, padValue: Scalar? = nil,
         readOnlyReferenceTo buffer: UnsafeRawBufferPointer) {
        
        // create tensor data reference to buffer
        let tensorData = TensorData(readOnlyReferenceTo: buffer,
                                    name: name ?? String(describing: Self.self))
        
        // create shape considering column major
        let shape = DataShape(extents: extents)
        assert(shape.elementCount == buffer.count,
               "shape count does not match buffer count")
        
        self.init(shape: shape, dataShape: shape, name: name,
                  padding: padding, padValue: padValue,
                  tensorData: tensorData, viewDataOffset: 0,
                  isShared: false, scalars: nil)
    }
    
    //--------------------------------------------------------------------------
    /// initialize with explicit labels
    init(_ items: Int, _ channels: Int, _ rows: Int, _ cols: Int,
         padding: [Padding]? = nil, padValue: Scalar? = nil,
         name: String? = nil, scalars: [Scalar]? = nil) {

        self.init(extents: [items, channels, rows, cols], name: name,
                  padding: padding, padValue: padValue,
                  scalars: scalars)
    }

    //-------------------------------------
    init<Seq>(_ items: Int, _ channels: Int, _ rows: Int, _ cols: Int,
              padding: [Padding]? = nil, padValue: Scalar? = nil,
              name: String? = nil, sequence: Seq) where
        Seq: Sequence, Seq.Element: AnyConvertable,
        Scalar: AnyConvertable
    {
        self.init(extents: [items, channels, rows, cols], name: name,
                  padding: padding, padValue: padValue,
                  scalars: Self.sequence2ScalarArray(sequence))
    }
}

//------------------------------------------------------------------------------
// NCHWTensor
public struct NCHWTensor<Scalar>: NCHWTensorView
where Scalar: ScalarConformance {
    // properties
    public let dataShape: DataShape
    public let isShared: Bool
    public let isVirtual: Bool
    public let padding: [Padding]
    public let padValue: Scalar
    public let shape: DataShape
    public var tensorData: TensorData!
    public var viewDataOffset: Int
    
    public init(shape: DataShape,
                dataShape: DataShape,
                name: String?,
                padding: [Padding]?,
                padValue: Scalar?,
                tensorData: TensorData?,
                viewDataOffset: Int,
                isShared: Bool,
                scalars: [Scalar]?) {
        self.shape = shape
        self.dataShape = dataShape
        self.padding = padding ?? [Padding(0)]
        self.padValue = padValue ?? Scalar()
        self.isShared = isShared
        self.isVirtual = padding != nil || dataShape != shape
        self.viewDataOffset = viewDataOffset
        self.tensorData = tensorData ?? initTensorData(name, scalars)
    }
}

extension NCHWTensor: CustomStringConvertible where Scalar: AnyConvertable {
    public var description: String { return formatted() }
}

//==============================================================================
/// NHWCTensorView
/// An NHWC tensor is a standard layout for use with cuDNN.
/// It has a layout of numerics organized as:
/// n: items
/// h: rows
/// w: cols
/// c: channels
public protocol NHWCTensorView: TensorView
where BoolView == NHWCTensor<Bool>, IndexView == NHWCTensor<IndexScalar> { }

public extension NHWCTensorView {
    //--------------------------------------------------------------------------
    /// shaped initializers
    
    //-------------------------------------
    /// with Array
    init(extents: [Int], name: String? = nil,
         padding: [Padding]? = nil, padValue: Scalar? = nil,
         scalars: [Scalar]? = nil) {
        
        let shape = DataShape(extents: extents)
        self.init(shape: shape, dataShape: shape, name: name,
                  padding: padding, padValue: padValue,
                  tensorData: nil, viewDataOffset: 0,
                  isShared: false, scalars: scalars)
    }

    //-------------------------------------
    /// with Sequence
    init<Seq>(extents: [Int], name: String? = nil,
              padding: [Padding]? = nil, padValue: Scalar? = nil,
              isColMajor: Bool = false, sequence: Seq) where
        Seq: Sequence, Seq.Element: AnyConvertable,
        Scalar: AnyConvertable
    {
        self.init(extents: extents, name: name,
                  padding: padding, padValue: padValue,
                  scalars: Self.sequence2ScalarArray(sequence))
    }

    //-------------------------------------
    /// with reference to read only buffer
    /// useful for memory mapped databases, or hardware device buffers
    init(extents: [Int], name: String? = nil,
         padding: [Padding]? = nil, padValue: Scalar? = nil,
         readOnlyReferenceTo buffer: UnsafeRawBufferPointer) {
        
        // create tensor data reference to buffer
        let tensorData = TensorData(readOnlyReferenceTo: buffer,
                                    name: name ?? String(describing: Self.self))
        
        // create shape considering column major
        let shape = DataShape(extents: extents)
        assert(shape.elementCount == buffer.count,
               "shape count does not match buffer count")
        
        self.init(shape: shape, dataShape: shape, name: name,
                  padding: padding, padValue: padValue,
                  tensorData: tensorData, viewDataOffset: 0,
                  isShared: false, scalars: nil)
    }
    
    //--------------------------------------------------------------------------
    /// initialize with explicit labels
    init(_ items: Int, _ rows: Int, _ cols: Int, _ channels: Int,
         name: String? = nil,
         padding: [Padding]? = nil, padValue: Scalar? = nil,
         scalars: [Scalar]? = nil) {

        self.init(extents: [items, rows, cols, channels], name: name,
                  padding: padding, padValue: padValue,
                  scalars: scalars)
    }

    //-------------------------------------
    init<Seq>(_ items: Int, _ rows: Int, _ cols: Int, _ channels: Int,
              padding: [Padding]? = nil, padValue: Scalar? = nil,
              name: String? = nil, sequence: Seq) where
        Seq: Sequence, Seq.Element: AnyConvertable,
        Scalar: AnyConvertable
    {
        self.init(extents:  [items, rows, cols, channels], name: name,
                  padding: padding, padValue: padValue,
                  scalars: Self.sequence2ScalarArray(sequence))
    }
}

//------------------------------------------------------------------------------
// NHWCTensor
public struct NHWCTensor<Scalar>: NHWCTensorView
where Scalar: ScalarConformance {
    // properties
    public let dataShape: DataShape
    public let isShared: Bool
    public let isVirtual: Bool
    public let padding: [Padding]
    public let padValue: Scalar
    public let shape: DataShape
    public var tensorData: TensorData!
    public var viewDataOffset: Int
    
    public init(shape: DataShape,
                dataShape: DataShape,
                name: String?,
                padding: [Padding]?,
                padValue: Scalar?,
                tensorData: TensorData?,
                viewDataOffset: Int,
                isShared: Bool,
                scalars: [Scalar]?) {
        self.shape = shape
        self.dataShape = dataShape
        self.padding = padding ?? [Padding(0)]
        self.padValue = padValue ?? Scalar()
        self.isShared = isShared
        self.isVirtual = padding != nil || dataShape != shape
        self.viewDataOffset = viewDataOffset
        self.tensorData = tensorData ?? initTensorData(name, scalars)
    }
}

extension NHWCTensor: CustomStringConvertible where Scalar: AnyConvertable {
    public var description: String { return formatted() }
}

//------------------------------------------------------------------------------
public extension NHWCTensor {
    // TODO: this probably isn't right now with the new TensorView behavior
    //       regarding padding. Test this
    //
    /// zero copy cast of a matrix of dense uniform scalars to NHWC
    init<M: MatrixView>(_ matrix: M, name: String? = nil) where
        M.Scalar: UniformDenseScalar,
        M.Scalar.Component == Scalar {
            let extents = [1, matrix.shape.extents[0],
                           matrix.shape.extents[1], M.Scalar.componentCount]
            
            let shape = DataShape(extents: extents)
            self.init(shape: shape,
                      dataShape: shape,
                      name: name,
                      padding: nil,
                      padValue: nil,
                      tensorData: matrix.tensorData,
                      viewDataOffset: matrix.viewDataOffset,
                      isShared: matrix.isShared,
                      scalars: nil)
    }
}
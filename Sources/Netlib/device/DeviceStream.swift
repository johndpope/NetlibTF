//******************************************************************************
//  Created by Edward Connell on 3/5/16
//  Copyright © 2016 Connell Research. All rights reserved.
//
import Foundation

//==============================================================================
// DeviceStream
/// A device stream is an asynchronous queue of commands executed on
/// the associated device. It is a class protocol treated as an abstract
/// driver interface.
public protocol DeviceStream:
    ObjectTracking,
    Logger,
    DeviceErrorHandling,
    StreamIntrinsicsProtocol,
    StreamGradientsProtocol
{
    //--------------------------------------------------------------------------
    // properties
    /// an event used to signal when all queued commands have completed
    var completionEvent: StreamEvent { get }
    /// the device the stream is associated with
    var device: ComputeDevice { get }
    /// a unique id used to identify the stream
    var id: Int { get }
    /// a name used to identify the stream
    var name: String { get }
    /// the internval of time to wait for an operation to complete
    var timeout: TimeInterval? { get set }
    
    /// for unit testing. It's part of the class protocol so that remote
    /// streams throw the error remotely.
    func throwTestError()
    
    //--------------------------------------------------------------------------
    // synchronization functions
    /// blocks the calling thread until the stream queue is empty
    func blockCallerUntilComplete() throws
    /// creates a StreamEvent
    func createEvent(options: StreamEventOptions) throws -> StreamEvent
    /// creates an artificial delay used to simulate work for debugging
    func debugDelay(seconds: Double) throws
    /// queues a stream event
    func record(event: StreamEvent) throws -> StreamEvent
    /// blocks caller until the event has occurred on this stream,
    /// then recorded and occurred on the other stream
    func sync(with other: DeviceStream, event: StreamEvent) throws
    /// blocks caller until the event has occurred
    func wait(for event: StreamEvent) throws
}

//==============================================================================
/// tryCatch
/// catches errors and reports them through the device error handling path
/// tries a throwing function and reports any errors thrown
public extension DeviceStream where Self: DeviceErrorHandling {
    func tryCatch(_ body: () throws -> Void) {
        guard lastError == nil else { return }
        do {
            try body()
        } catch {
            reportDevice(error: error, event: completionEvent)
        }
    }
    
    func tryCatch<T: DefaultInitializer>(_ body: () throws -> T) -> T {
        guard lastError == nil else { return T() }
        do {
            return try body()
        } catch {
            reportDevice(error: error, event: completionEvent)
            return T()
        }
    }
}

//==============================================================================
/// LocalDeviceStream
public protocol LocalDeviceStream: DeviceStream { }

public extension LocalDeviceStream {
    //--------------------------------------------------------------------------
    /// defaultDeviceErrorHandler
    func defaultDeviceErrorHandler(error: Error) {
        device.deviceErrorHandler(error)
    }
}

//==============================================================================
// StreamIntrinsicsProtocol
/// The required set of base level intrinsic functions for a `DeviceStream`
///
public protocol StreamIntrinsicsProtocol {
    /// Computes the absolute value of the specified TensorView element-wise.
    func abs<T>(x: T, result: inout T)
        where T: TensorView, T.Scalar: SignedNumeric
    /// Adds two tensors and produces their sum.
    func add<T>(lhs: T, rhs: T, result: inout T)
        where T: TensorView, T.Scalar: Numeric
    /// Returns `true` if all scalars are `true`. Otherwise, returns `false`.
    /// - Parameter x: the tensor value
    /// - Parameter axes: The axes to reduce
    func all<T>(x: T, axes: Vector<IndexScalar>?, result: inout T)
        where T: TensorView, T.Scalar == Bool
    /// Returns `true` if any scalars are`true`. Otherwise, returns `false`.
    /// - Parameter x: the tensor value
    /// - Parameter axes: The axes to reduce
    func any<T>(x: T, axes: Vector<IndexScalar>?, result: inout T)
        where T: TensorView, T.Scalar == Bool
    /// Performs a pointwise comparison within the specified tolerance
    func approximatelyEqual<T>(lhs: T, rhs: T,
                               tolerance: T.Scalar,
                               result: inout T.BoolView) where
        T: TensorView, T.Scalar: AnyFloatingPoint,
        T.BoolView.Scalar == Bool
    /// Returns the indices of the maximum values along the specified axes. The
    /// reduced dimensions are removed.
    /// - Parameter x: the tensor value
    /// - Parameter axes: The axes to reduce
    /// - Precondition: Each value in `axes` must be in the range `-rank..<rank`.
    func argmax<T>(x: T, axes: Vector<IndexScalar>?, result: inout T.IndexView)
        where
        T: TensorView, T.Scalar: Numeric,
        T.IndexView.Scalar == IndexScalar
    /// Returns the indices of the minimum values along the specified axes. The
    /// reduced dimensions are removed.
    /// - Parameter x: the tensor value
    /// - Parameter axes: The axes to reduce
    /// - Precondition: Each value in `axes` must be in the range `-rank..<rank`.
    func argmin<T>(x: T, axes: Vector<IndexScalar>?, result: inout T.IndexView)
        where
        T: TensorView, T.Scalar: Numeric,
        T.IndexView.Scalar == IndexScalar
    /// Sums the absolute value of the input along the specified axes
    /// - Parameter x: the tensor value
    /// - Parameter axes: The axes to reduce
    func asum<T>(x: T, axes: Vector<IndexScalar>?, result: inout T) where
        T: TensorView, T.Scalar: AnyNumeric
    /// cast scalar types
    /// - Parameter from: the input data
    /// - Parameter result: the output
    func cast<T, R>(from: T, to result: inout R) where
        T: TensorView, T.Scalar: AnyConvertable,
        R: TensorView, R.Scalar: AnyConvertable
    /// Computes the ceiling of the specified TensorView element-wise.
    func ceil<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: FloatingPoint
    /// Concatenates tensors along the specified axis.
    /// - Precondition: The tensors must have the same dimensions, except for the
    ///                 specified axis.
    /// - Precondition: The axis must be in the range `-rank..<rank`.
    func concatenate<T>(view: T, with other: T, alongAxis axis: Int,
                        result: inout T) where T: TensorView
    /// Computes the element-wise `cos`
    func cos<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: FloatingPoint
    /// Computes the element-wise `cosh`
    func cosh<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: FloatingPoint
    /// Returns the quotient of dividing the first TensorView by the second.
    /// - Note: `/` supports broadcasting.
    func div<T>(lhs: T, rhs: T, result: inout T)
        where T: TensorView, T.Scalar: FloatingPoint
    /// Computes `lhs == rhs` element-wise and returns a `TensorView` of Boolean
    /// scalars.
    /// - Note: `.==` supports broadcasting.
    func equal<T>(lhs: T, rhs: T, result: inout T.BoolView)
        where T: TensorView
    /// Computes the element-wise `exp`
    func exp<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: FloatingPoint
    /// fills the view with the scalar value
    func fill<T>(x: inout T, with: T.Scalar) where T: TensorView
    /// fills the view with the spatial sequential index
    func fillWithIndex<T>(result: inout T, startAt: Int) where
        T: TensorView, T.Scalar: AnyNumeric
    /// Computes the element-wise `floor`
    func floor<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: FloatingPoint
    /// Computes `lhs > rhs` element-wise and returns a `TensorView` of Boolean
    /// scalars.
    func greater<T>(lhs: T, rhs: T, result: inout T.BoolView)
        where T: TensorView, T.Scalar: Numeric
    /// Computes `lhs >= rhs` element-wise and returns a `TensorView` of Boolean
    /// scalars.
    func greaterOrEqual<T>(lhs: T, rhs: T, result: inout T.BoolView)
        where T: TensorView, T.Scalar: Numeric
    /// Computes `lhs < rhs` element-wise and returns a `TensorView` of Boolean
    /// scalars.
    func less<T>(lhs: T, rhs: T, result: inout T.BoolView)
        where T: TensorView, T.Scalar: Numeric
    /// lessEqual
    /// Computes `lhs <= rhs` element-wise and returns a `TensorView` of Boolean
    /// scalars.
    func lessOrEqual<T>(lhs: T, rhs: T, result: inout T.BoolView)
        where T: TensorView, T.Scalar: Numeric
    /// Computes the element-wise `log`
    func log<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: AnyFloatingPoint
    /// Computes the element-wise `!x`
    func logicalNot<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar == Bool
    /// Computes the element-wise `lhs && rhs`
    func logicalAnd<T>(lhs: T, rhs: T, result: inout T) where
        T: TensorView, T.Scalar == Bool
    /// Computes the element-wise `lhs || rhs`
    func logicalOr<T>(lhs: T, rhs: T, result: inout T) where
        T: TensorView, T.Scalar == Bool
    /// Computes the element-wise `logSoftmax`
    func logSoftmax<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: FloatingPoint
    /// Performs matrix multiplication with another TensorView and produces the
    /// result.
    func matmul<T>(lhs: T, rhs: T, result: inout T) where
        T: TensorView, T.Scalar: Numeric
    /// Returns the maximum values along the specified axes. The reduced
    /// dimensions are removed.
    /// - Parameter axes: The dimensions to reduce.
    /// - Precondition: Each value in `axes` must be in the range `-rank..<rank`.
    func max<T>(x: T, squeezingAxes axes: [Int], result: inout T) where
        T: TensorView, T.Scalar: Numeric
    /// Computes the element-wise maximum of two tensors.
    /// - Note: `max` supports broadcasting.
    func maximum<T>(lhs: T, rhs: T, result: inout T) where
        T: TensorView, T.Scalar: Numeric
    /// Returns the arithmetic mean along the specified axes. The reduced
    /// dimensions are removed.
    /// - Parameter x: the tensor value
    /// - Parameter axes: The axes to reduce
    /// - Precondition: Each value in `axes` must be in the range `-rank...rank`.
    func mean<T>(x: T, axes: Vector<IndexScalar>?, result: inout T) where
        T: TensorView, T.Scalar: Numeric
    /// Returns the minimum values along the specified axes. The reduced
    /// dimensions are removed.
    /// - Parameter axes: The dimensions to reduce.
    /// - Precondition: Each value in `axes` must be in the range `-rank..<rank`.
    func min<T>(x: T, squeezingAxes axes: [Int], result: inout T) where
        T: TensorView, T.Scalar: Numeric
    /// Computes the element-wise minimum of two tensors.
    /// - Note: `max` supports broadcasting.
    func minimum<T>(lhs: T, rhs: T, result: inout T) where
        T: TensorView, T.Scalar: Numeric
    /// Returns the remainder of dividing the first TensorView by the second.
    /// - Note: `%` supports broadcasting.
    func mod<T>(lhs: T, rhs: T, result: inout T)
        where T: TensorView, T.Scalar: Numeric
    /// mul
    func mul<T>(lhs: T, rhs: T, result: inout T)
        where T: TensorView, T.Scalar: Numeric
    /// Computes the element-wise negation
    func neg<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: SignedNumeric
    /// Computes `lhs != rhs` element-wise and returns a `TensorView` of Boolean
    /// scalars.
    /// - Note: `.==` supports broadcasting.
    func notEqual<T>(lhs: T, rhs: T, result: inout T.BoolView)
        where T: TensorView, T.Scalar: Numeric
    /// Computes the element-wise `x**y`
    func pow<T>(x: T, y: T, result: inout T)
        where T: TensorView, T.Scalar: AnyNumeric
    /// Product of the input elements to produce a scalar
    /// - Parameter x: the tensor value
    /// - Parameter axes: The axes to reduce
    /// - Precondition: Each value in `axes` must be in the range `-rank...rank`.
    func prod<T>(x: T, axes: Vector<IndexScalar>?, result: inout T) where
        T: TensorView, T.Scalar: Numeric
    /// Computes the element-wise `rsqrt`
    func rsqrt<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: FloatingPoint
    /// Replaces elements of `x` with `other` in the lanes where `mask` is`true`
    ///
    /// - Precondition: `x` and `other` must have the same shape. If
    ///   `x` and `other` are scalar, then `mask` must also be scalar. If
    ///   `x` and `other` have rank greater than or equal to `1`, then `mask`
    ///   must be either have the same shape as `self` or be a 1-D `TensorView` such
    ///   that `mask.scalarCount == self.shape[0]`.
    func replacing<T>(x: T, with other: T, where mask: T.BoolView,
                      result: inout T)
        where T: TensorView
    /// Computes the element-wise `sin`
    func sin<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: FloatingPoint
    /// Computes the element-wise `sinh`
    func sinh<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: FloatingPoint
    /// Computes the element-wise `square`
    func square<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: Numeric
    /// Computes the element-wise `(lhs - rhs)**2`
    func squaredDifference<T>(lhs: T, rhs: T, result: inout T) where
        T: TensorView, T.Scalar: Numeric
    /// Computes the element-wise `sqrt`
    func sqrt<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: FloatingPoint
    /// subtract
    func subtract<T>(lhs: T, rhs: T, result: inout T)
        where T: TensorView, T.Scalar: Numeric
    /// Sums the input along the specified axes
    /// - Parameter x: the tensor value
    /// - Parameter axes: The axes to reduce
    func sum<T>(x: T, axes: Vector<IndexScalar>?,
                result: inout T) where
        T: TensorView, T.Scalar: Numeric
    /// Computes the element-wise `tan`
    func tan<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: FloatingPoint
    /// Computes the element-wise `tanh`
    func tanh<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: FloatingPoint
}

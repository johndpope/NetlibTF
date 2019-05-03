//******************************************************************************
//  Created by Edward Connell on 4/16/19
//  Copyright © 2019 Connell Research. All rights reserved.
//
import Foundation

public extension CpuStream {
    //--------------------------------------------------------------------------
    /// abs
    func abs<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: Numeric, T.Scalar.Magnitude == T.Scalar
    {
        queue(#function, x, &result) { x, result in
            x.map(to: &result) { $0.magnitude }
        }
    }
    
    //--------------------------------------------------------------------------
    /// add
    func add<T>(lhs: T, rhs: T, result: inout T) where
        T : TensorView, T.Scalar : Numeric
    {
        queue(#function, lhs, rhs, &result) { lhs, rhs, results in
            zip(lhs, rhs).map(to: &results) { $0 + $1 }
        }
    }
    
    //--------------------------------------------------------------------------
    /// all
    func all<T>(x: T, axes: Vector<IndexScalar>?, result: inout T) where
        T : TensorView, T.Scalar == Bool
    {
        queue(#function, x, &result) { x, result in
            let index = result.startIndex
            for value in x where !value {
                result[index] = false
                return
            }
            result[index] = true
        }
    }
    
    //--------------------------------------------------------------------------
    /// any
    func any<T>(x: T, axes: Vector<IndexScalar>?, result: inout T) where
        T : TensorView, T.Scalar == Bool
    {
        queue(#function, x, &result) { x, result in
            let index = result.startIndex

            for value in x where value {
                result[index] = true
                return
            }
            result[index] = false
        }
    }
    
    //--------------------------------------------------------------------------
    /// approximatelyEqual
    func approximatelyEqual<T>(lhs: T, rhs: T,
                               tolerance: T.Scalar,
                               result: inout T.BoolView) where
        T : TensorView, T.Scalar : AnyFloatingPoint,
        T.BoolView.Scalar == Bool
    {
        queue(#function, lhs, rhs, &result) { lhs, rhs, results in
            zip(lhs, rhs).map(to: &results) { $0.0 - $0.1 <= tolerance }
        }
    }
    
    //--------------------------------------------------------------------------
    /// argmax
    func argmax<T>(x: T, axes: Vector<IndexScalar>?, result: inout T.IndexView)
        where T: TensorView, T.Scalar: Numeric,
        T.IndexView.Scalar == IndexScalar
    {
    }
    
    //--------------------------------------------------------------------------
    /// argmin
    func argmin<T>(x: T, axes: Vector<IndexScalar>?, result: inout T.IndexView)
        where T: TensorView, T.Scalar: Numeric,T.IndexView.Scalar == IndexScalar
    {
        
    }
    
    //--------------------------------------------------------------------------
    /// asum
    func asum<T>(x: T, axes: Vector<IndexScalar>?, result: inout T) where
        T: TensorView, T.Scalar: Numeric, T.Scalar.Magnitude == T.Scalar
    {
        queue(#function, x, &result) { x, result in
            x.reduce(to: &result, T.Scalar.zero) {
                $0 + $1.magnitude
            }
        }
    }
    
    //--------------------------------------------------------------------------
    /// cast
    func cast<T, R>(from: T, to result: inout R) where
        T : TensorView, R : TensorView, T.Scalar : AnyConvertable,
        R.Scalar : AnyConvertable
    {
        
    }
    
    //--------------------------------------------------------------------------
    /// ceil
    func ceil<T>(x: T, result: inout T) where
        T : TensorView, T.Scalar : AnyFloatingPoint
    {
        queue(#function, x, &result) { x, result in
            x.map(to: &result) {
                T.Scalar(any: Foundation.ceilf($0.asFloat))
            }
        }
    }
    
    //--------------------------------------------------------------------------
    /// concatenate
    func concatenate<T>(view: T, with other: T,
                        alongAxis axis: Int, result: inout T) where
        T: TensorView
    {
        
    }
    
    //--------------------------------------------------------------------------
    /// cos
    func cos<T>(x: T, result: inout T) where
        T : TensorView, T.Scalar : AnyFloatingPoint
    {
        queue(#function, x, &result) { x, result in
            x.map(to: &result) {
                T.Scalar(any: Foundation.cos($0.asFloat))
            }
        }
    }
    
    //--------------------------------------------------------------------------
    /// cosh
    func cosh<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: AnyFloatingPoint
    {
        queue(#function, x, &result) { x, result in
            x.map(to: &result) {
                T.Scalar(any: Foundation.cosh($0.asFloat))
            }
        }
    }
    
    //--------------------------------------------------------------------------
    /// div
    func div<T>(lhs: T, rhs: T, result: inout T) where
        T : TensorView, T.Scalar : AnyFloatingPoint
    {
        queue(#function, lhs, rhs, &result) { lhs, rhs, results in
            zip(lhs, rhs).map(to: &results) { $0 / $1 }
        }
    }
    
    //--------------------------------------------------------------------------
    /// equal
    func equal<T>(lhs: T, rhs: T, result: inout T.BoolView) where
        T: TensorView, T.Scalar: Equatable,
        T.BoolView.Scalar == Bool
    {
        queue(#function, lhs, rhs, &result) { lhs, rhs, results in
            zip(lhs, rhs).map(to: &results) { $0 == $1 }
        }
    }
    
    //--------------------------------------------------------------------------
    /// exp
    func exp<T>(x: T, result: inout T) where
        T : TensorView, T.Scalar : AnyFloatingPoint
    {
        queue(#function, x, &result) { x, result in
            x.map(to: &result) {
                T.Scalar(any: Foundation.log($0.asFloat))
            }
        }
    }
    
    //--------------------------------------------------------------------------
    /// fill(result:with:
    /// NOTE: this can be much faster, doesn't need to be ordered access
    func fill<T>(_ result: inout T, with value: T.Scalar) where T : TensorView {
        queue(#function, &result) { result in
            for index in result.indices {
                result[index] = value
            }
        }
    }
    
    //--------------------------------------------------------------------------
    /// fillWithIndex(x:startAt:
    func fillWithIndex<T>(_ result: inout T, startAt: Int) where
        T : TensorView, T.Scalar: AnyNumeric
    {
        queue(#function, &result) { result in
            var value = startAt
            for index in result.indices {
                result[index] = T.Scalar(any: value)
                value += 1
            }
        }
    }

    //--------------------------------------------------------------------------
    /// floor
    func floor<T>(x: T, result: inout T) where
        T : TensorView, T.Scalar : AnyFloatingPoint
    {
        queue(#function, x, &result) { x, result in
            x.map(to: &result) {
                T.Scalar(any: Foundation.floorf($0.asFloat))
            }
        }
    }
    
    //--------------------------------------------------------------------------
    /// greater
    func greater<T>(lhs: T, rhs: T, result: inout T.BoolView) where
        T : TensorView, T.Scalar: Comparable, T.BoolView.Scalar == Bool
    {
        queue(#function, lhs, rhs, &result) { lhs, rhs, res in
            zip(lhs, rhs).map(to: &res) { $0 > $1 }
        }
    }
    
    //--------------------------------------------------------------------------
    /// greaterOrEqual
    func greaterOrEqual<T>(lhs: T, rhs: T, result: inout T.BoolView) where
        T : TensorView, T.Scalar: Comparable, T.BoolView.Scalar == Bool
    {
        queue(#function, lhs, rhs, &result) { lhs, rhs, res in
            zip(lhs, rhs).map(to: &res) { $0 >= $1 }
        }
    }

    //--------------------------------------------------------------------------
    /// less
    func less<T>(lhs: T, rhs: T, result: inout T.BoolView) where
        T : TensorView, T.Scalar: Comparable, T.BoolView.Scalar == Bool
    {
        queue(#function, lhs, rhs, &result) { lhs, rhs, res in
            zip(lhs, rhs).map(to: &res) { $0 < $1 }
        }
    }

    //--------------------------------------------------------------------------
    /// lessOrEqual
    func lessOrEqual<T>(lhs: T, rhs: T, result: inout T.BoolView) where
        T : TensorView, T.Scalar: Comparable, T.BoolView.Scalar == Bool
    {
        queue(#function, lhs, rhs, &result) { lhs, rhs, res in
            zip(lhs, rhs).map(to: &res) { $0 <= $1 }
        }
    }

    //--------------------------------------------------------------------------
    /// log(x:result:
    func log<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: AnyFloatingPoint
    {
        queue(#function, x, &result) { x, result in
            x.map(to: &result) {
                T.Scalar(any: Foundation.log($0.asFloat))
            }
        }
    }
    
    //--------------------------------------------------------------------------
    /// logicalNot(x:result:
    func logicalNot<T>(x: T, result: inout T) where
        T : TensorView, T.Scalar == Bool
    {
        queue(#function, x, &result) { $0.map(to: &$1) { !$0 } }
    }
    
    //--------------------------------------------------------------------------
    /// logicalAnd(x:result:
    func logicalAnd<T>(lhs: T, rhs: T, result: inout T) where
        T : TensorView, T.Scalar == Bool
    {
        queue(#function, lhs, rhs, &result) { lhs, rhs, results in
            zip(lhs, rhs).map(to: &results) { $0 && $1 }
        }
    }

    //--------------------------------------------------------------------------
    /// logicalOr(x:result:
    func logicalOr<T>(lhs: T, rhs: T, result: inout T) where
        T : TensorView, T.Scalar == Bool
    {
        queue(#function, lhs, rhs, &result) { lhs, rhs, results in
            zip(lhs, rhs).map(to: &results) { $0 || $1 }
        }
    }

    //--------------------------------------------------------------------------
    /// logSoftmax(x:result:
    func logSoftmax<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: AnyFloatingPoint
    {
    }

    //--------------------------------------------------------------------------
    /// matmul(lhs:rhs:result:
    func matmul<T>(lhs: T, rhs: T, result: inout T) where
        T : TensorView, T.Scalar : Numeric
    {
        
    }
    
    func max<T>(x: T, squeezingAxes axes: [Int], result: inout T) where T : TensorView, T.Scalar : Numeric {
        
    }
    
    //--------------------------------------------------------------------------
    /// maximum(lhs:rhs:result:
    func maximum<T>(lhs: T, rhs: T, result: inout T) where
        T : TensorView, T.Scalar : Comparable
    {
        queue(#function, lhs, rhs, &result) { lhs, rhs, results in
            zip(lhs, rhs).map(to: &results) { $0 >= $1 ? $0 : $1 }
        }
    }
    
    func mean<T>(x: T, axes: Vector<IndexScalar>?, result: inout T) where T : TensorView, T.Scalar : Numeric {
        
    }
    
    func min<T>(x: T, squeezingAxes axes: [Int], result: inout T) where T : TensorView, T.Scalar : Numeric {
        
    }
    
    //--------------------------------------------------------------------------
    /// minimum(lhs:rhs:result:
    func minimum<T>(lhs: T, rhs: T, result: inout T) where
        T : TensorView, T.Scalar : Comparable
    {
        queue(#function, lhs, rhs, &result) { lhs, rhs, results in
            zip(lhs, rhs).map(to: &results) { $0 <= $1 ? $0 : $1 }
        }
    }
    
    //--------------------------------------------------------------------------
    // mod
    func mod<T>(lhs: T, rhs: T, result: inout T) where
        T : TensorView, T.Scalar : AnyFloatingPoint
    {
        queue(#function, lhs, rhs, &result) { lhs, rhs, results in
            zip(lhs, rhs).map(to: &results) {
                T.Scalar(any: fmodf($0.asFloat, $1.asFloat))
            }
        }
    }

    //--------------------------------------------------------------------------
    // mul
    func mul<T>(lhs: T, rhs: T, result: inout T) where
        T : TensorView, T.Scalar : Numeric
    {
        queue(#function, lhs, rhs, &result) { lhs, rhs, results in
            zip(lhs, rhs).map(to: &results) { $0 * $1 }
        }
    }
    
    //--------------------------------------------------------------------------
    // neg
    func neg<T>(x: T, result: inout T) where
        T : TensorView, T.Scalar : SignedNumeric
    {
        queue(#function, x, &result) { x, result in
            x.map(to: &result) { -$0 }
        }
    }
    
    //--------------------------------------------------------------------------
    // notEqual
    func notEqual<T>(lhs: T, rhs: T, result: inout T.BoolView) where
        T: TensorView, T.Scalar: Equatable, T.BoolView.Scalar == Bool
    {
        queue(#function, lhs, rhs, &result) { lhs, rhs, results in
            zip(lhs, rhs).map(to: &results) { $0 != $1 }
        }
    }

    //--------------------------------------------------------------------------
    // pow
    // TODO there needs to be a generic math library!
    func pow<T>(x: T, y: T, result: inout T) where
        T : TensorView, T.Scalar : AnyNumeric
    {
        queue(#function, x, y, &result) { x, y, results in
            zip(x, y).map(to: &results) {
                T.Scalar(any: Foundation.pow($0.asDouble, $1.asDouble))
            }
        }
    }

    //--------------------------------------------------------------------------
    // prod
    func prod<T>(x: T, axes: Vector<IndexScalar>?, result: inout T) where
        T : TensorView, T.Scalar : AnyNumeric
    {
        let one = T.Scalar(any: 1)
//        if let axes = axes {
//            queue(#function, x, axes, &result) { x, axes, results in
//                x.reduce(to: &results, T.Scalar(any: 1)) { $0 * $1 }
//            }
//        } else {
            queue(#function, x, &result) { x, results in
                x.reduce(to: &results, one) { $0 * $1 }
            }
//        }
    }
    
    //--------------------------------------------------------------------------
    // rsqrt
    func rsqrt<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: AnyFloatingPoint
    {
        queue(#function, x, &result) { x, result in
            x.map(to: &result) { 1 / Foundation.sqrt($0) }
        }
    }

    //--------------------------------------------------------------------------
    // replacing
    func replacing<T>(x: T, with other: T, where mask: T.BoolView,
                      result: inout T) where T : TensorView
    {
        queue(#function, x, other, &result) { x, other, result in
            
        }
    }
    
    //--------------------------------------------------------------------------
    // sin
    func sin<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: AnyFloatingPoint
    {
        queue(#function, x, &result) { x, result in
            x.map(to: &result) {
                T.Scalar(any: Foundation.sinf($0.asFloat))
            }
        }
    }

    
    //--------------------------------------------------------------------------
    // sinh
    func sinh<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: AnyFloatingPoint
    {
        queue(#function, x, &result) { x, result in
            x.map(to: &result) {
                T.Scalar(any: Foundation.sinhf($0.asFloat))
            }
        }
    }

    //--------------------------------------------------------------------------
    // square
    func square<T>(x: T, result: inout T) where
        T : TensorView, T.Scalar : Numeric
    {
        queue(#function, x, &result) { x, result in
            x.map(to: &result) { $0 * $0 }
        }
    }
    
    //--------------------------------------------------------------------------
    // squaredDifference
    func squaredDifference<T>(lhs: T, rhs: T, result: inout T) where
        T : TensorView, T.Scalar : Numeric
    {
        queue(#function, lhs, rhs, &result) { lhs, rhs, result in
            zip(lhs, rhs).map(to: &result) {
                let diff = $0 - $1
                return diff * diff
            }
        }
    }
    
    //--------------------------------------------------------------------------
    // sqrt
    func sqrt<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: AnyFloatingPoint
    {
        queue(#function, x, &result) { x, result in
            x.map(to: &result) { Foundation.sqrt($0) }
        }
    }
    
    //--------------------------------------------------------------------------
    // subtract
    func subtract<T>(lhs: T, rhs: T, result: inout T) where
        T : TensorView, T.Scalar : Numeric
    {
        queue(#function, lhs, rhs, &result) { lhs, rhs, results in
            zip(lhs, rhs).map(to: &results) { $0 - $1 }
        }
    }
    
    //--------------------------------------------------------------------------
    // sum
    func sum<T>(x: T, axes: Vector<IndexScalar>?, result: inout T) where
        T : TensorView, T.Scalar : Numeric
    {
        queue(#function, x, &result) { x, result in
            x.reduce(to: &result, T.Scalar.zero) { $0 + $1 }
        }
    }
    
    //--------------------------------------------------------------------------
    // tan
    func tan<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: AnyFloatingPoint
    {
        queue(#function, x, &result) { x, result in
            x.map(to: &result) {
                T.Scalar(any: Foundation.tanf($0.asFloat))
            }
        }
    }

    //--------------------------------------------------------------------------
    // tanh
    func tanh<T>(x: T, result: inout T) where
        T: TensorView, T.Scalar: AnyFloatingPoint
    {
        queue(#function, x, &result) { x, result in
            x.map(to: &result) {
                T.Scalar(any: Foundation.tanhf($0.asFloat))
            }
        }
    }
}

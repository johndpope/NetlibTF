# NetlibTF

## Overview
This project extracts some key Netlib IP that I have reworked and enhanced specifically to meet the design goals of the Google Swift 4 TensorFlow project as I understand them.

The code is in early stages and needs signficant testing along with performance and usuability refinement.

## Core Design Goals
* Optimal defaults for all configuration parameters so the user can have a good experience with no upfront training or special effort
* Simplified local and remote compute device management for more sophisticated applications
* A single uniform data representation that is used on both the application thread in “Swift space”, and transparently used on local and remote accelerators.
* Minimal memory consumption and zero copy capability API variants for “careful” designs
* Convenient expression composition for “casual” prototype designs
* Transparent asynchronous execution model to minimize device stalling and efficiently use collections of devices with continuously variable latencies, both local and remote.
* An execution model that can leverage existing standard driver models such as Cuda and OpenCL.
* Integrated fine grain logging that enables selection of both message level (error, warning, diagnostic) and message category.
* Enable clear closure opportunities for compiler vectorization
* Extensible driver model without requiring a rebuild
* Reusable Function repository for rapid model development using “expert” designed functional components.

## Proposed Execution Model
The design goal is to have an asynchronous execution model that is transparent to the user and can leverage existing driver infrastructure such as Cuda, OpenCL, and other proprietary models such as Google TPUs.
I propose adopting an asynchronous stream based driver model to meet this goal for both local and remote devices.

## Simple Examples of the Experience
The following is a complete program. It initializes a matrix with a sequence then takes the sum. It uses shortcut syntax to specify the matrix extents (3, 5)
```swift
let matrix = Matrix<Float>(3, 5, sequence: 0..<15)
let sum = matrix.sum().scalarValue()
assert(sum == 105.0)
```

This selects and sums a 3D sub region
- initialize a volume using explicit extents
- fill with indexes on the default device
- on the device create a sub view and take the sum 
- return the scalar value back to the app thread
```swift
let volume = Volume<Int32>(extents: [3, 4, 5]).filledWithIndex()
let subView = volume.view(at: [1, 1, 1], extents: [2, 2, 2])
let subViewSum = sum(subView).scalarValue()
assert(subViewSum == 312)
```
If we print with formatting
```swift
print(volume.formatted(scalarFormat: (2,0)))
```
```sh
TensorView extents: [3, 4, 5] paddedExtents: [3, 4, 5]
at index: [0, 0, 0]
===================
  at index: [0, 0, 0]
  -------------------
   0  1  2  3  4 
   5  6  7  8  9 
  10 11 12 13 14 
  15 16 17 18 19 

at index: [1, 0, 0]
===================
  at index: [1, 0, 0]
  -------------------
  20 21 22 23 24 
  25 26 27 28 29 
  30 31 32 33 34 
  35 36 37 38 39 

at index: [2, 0, 0]
===================
  at index: [2, 0, 0]
  -------------------
  40 41 42 43 44 
  45 46 47 48 49 
  50 51 52 53 54 
  55 56 57 58 59 
```
```swift
print(subView.formatted(scalarFormat: (2,0)))
```
```sh
TensorView extents: [2, 2, 2] paddedExtents: [2, 2, 2]
at index: [0, 0, 0]
===================
  at index: [0, 0, 0]
  -------------------
  26 27 
  31 32 

at index: [1, 0, 0]
===================
  at index: [1, 0, 0]
  -------------------
  46 47 
  51 52 
```
All tensor views are able to repeat data through indexing. No matter the extents, `volume` only uses the shared storage
from `value`.
```swift
let volume = Volume<Int32>(extents: [2, 3, 10], repeating: Volume(42))
print(volume.formatted(scalarFormat: (2,0)))
```        
Repeating any pattern whether it matches any dimensions is allowed. These repeat a row and column vectors.
No matter the extents, `matrix` only uses the shared storage from `rowVector` and repeats it through indexing.
```swift
let rowVector = Matrix<Int32>(1, 10, sequence: 0..<10)
let rmatrix = Matrix(extents: [10, 10], repeating: rowVector)
print(rmatrix.formatted(scalarFormat: (2,0)))

let colVector = Matrix<Int32>(10, 1, sequence: 0..<10)
let cmatrix = Matrix(extents: [10, 10], repeating: colVector)
print(cmatrix.formatted(scalarFormat: (2,0)))
```
```sh
TensorView extents: [10, 10] paddedExtents: [10, 10]
at index: [0, 0]
----------------
 0  1  2  3  4  5  6  7  8  9 
 0  1  2  3  4  5  6  7  8  9 
 0  1  2  3  4  5  6  7  8  9 
 0  1  2  3  4  5  6  7  8  9 
 0  1  2  3  4  5  6  7  8  9 
 0  1  2  3  4  5  6  7  8  9 
 0  1  2  3  4  5  6  7  8  9 
 0  1  2  3  4  5  6  7  8  9 
 0  1  2  3  4  5  6  7  8  9 
 0  1  2  3  4  5  6  7  8  9 

TensorView extents: [10, 10] paddedExtents: [10, 10]
at index: [0, 0]
----------------
 0  0  0  0  0  0  0  0  0  0 
 1  1  1  1  1  1  1  1  1  1 
 2  2  2  2  2  2  2  2  2  2 
 3  3  3  3  3  3  3  3  3  3 
 4  4  4  4  4  4  4  4  4  4 
 5  5  5  5  5  5  5  5  5  5 
 6  6  6  6  6  6  6  6  6  6 
 7  7  7  7  7  7  7  7  7  7 
 8  8  8  8  8  8  8  8  8  8 
 9  9  9  9  9  9  9  9  9  9 
```




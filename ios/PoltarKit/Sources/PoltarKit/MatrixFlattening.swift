import Foundation
#if canImport(simd)
import simd
#endif

/// A 4x4 column-major transform stored as 16 numbers, free of any scanner's types.
public enum MatrixFlattening {
    public static let identity: [Double] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]

    /// Pure rotation about Y plus a translation. Used by tests and sample data.
    public static func transform(yawRadians a: Double, x: Double, y: Double, z: Double) -> [Double] {
        [cos(a), 0, -sin(a), 0,  0, 1, 0, 0,  sin(a), 0, cos(a), 0,  x, y, z, 1]
    }

    #if canImport(simd)
    public static func flatten(_ m: simd_float4x4) -> [Double] {
        [m.columns.0, m.columns.1, m.columns.2, m.columns.3].flatMap { c in
            [Double(c.x), Double(c.y), Double(c.z), Double(c.w)]
        }
    }
    #endif
}

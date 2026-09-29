import Foundation
import SceneKit

/// Loads the packed HumanShape PCA basis (mean mesh + top-K eigenvectors + faces)
/// from body_basis.bin and reconstructs a parametric body mesh given PC scores.
///
/// Binary layout (little-endian):
///   uint32 vertCount, faceCount, kComponents
///   float32 mean[V*3]
///   float32 basis[K*V*3]   (pre-scaled by sqrt(evalue): pass z-scores)
///   uint32  faces[F*3]
///
/// Coords are SceneKit meters: +X right, +Y up, +Z forward.
final class ParametricBody {
    nonisolated(unsafe) static let shared: ParametricBody? = ParametricBody.load()

    let vertCount: Int
    let faceCount: Int
    let kComponents: Int
    private let mean: [Float]               // V*3
    private let basis: [[Float]]            // [K][V*3]
    private let faces: Data                 // raw uint32[F*3]

    private init(vertCount: Int, faceCount: Int, kComponents: Int,
                 mean: [Float], basis: [[Float]], faces: Data) {
        self.vertCount = vertCount
        self.faceCount = faceCount
        self.kComponents = kComponents
        self.mean = mean
        self.basis = basis
        self.faces = faces
    }

    private static func load() -> ParametricBody? {
        guard let url = Bundle.main.url(forResource: "body_basis", withExtension: "bin"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        var off = 0
        func readU32() -> UInt32 {
            let v = data.subdata(in: off..<(off+4)).withUnsafeBytes { $0.load(as: UInt32.self) }
            off += 4
            return v
        }
        let V = Int(readU32())
        let F = Int(readU32())
        let K = Int(readU32())

        let meanByteCount = V * 3 * MemoryLayout<Float>.size
        let mean = data.subdata(in: off..<(off+meanByteCount)).withUnsafeBytes {
            Array($0.bindMemory(to: Float.self))
        }
        off += meanByteCount

        var basis = [[Float]]()
        basis.reserveCapacity(K)
        let compByteCount = V * 3 * MemoryLayout<Float>.size
        for _ in 0..<K {
            let comp = data.subdata(in: off..<(off+compByteCount)).withUnsafeBytes {
                Array($0.bindMemory(to: Float.self))
            }
            basis.append(comp)
            off += compByteCount
        }

        let facesByteCount = F * 3 * MemoryLayout<UInt32>.size
        let faces = data.subdata(in: off..<(off+facesByteCount))

        return ParametricBody(vertCount: V, faceCount: F, kComponents: K,
                              mean: mean, basis: basis, faces: faces)
    }

    /// Reconstruct vertex positions for a given set of PC z-scores.
    /// Missing/extra scores are clamped/ignored. Returns flat V*3 array.
    func vertices(scores: [Float]) -> [Float] {
        var out = mean
        let usedK = min(scores.count, kComponents)
        for k in 0..<usedK {
            let s = scores[k]
            if s == 0 { continue }
            let comp = basis[k]
            for i in 0..<out.count {
                out[i] += s * comp[i]
            }
        }
        return out
    }

    /// Build an SCNGeometry from vertex positions reconstructed at `scores`.
    /// Recomputes per-vertex normals via face-area-weighted averaging.
    func makeGeometry(scores: [Float]) -> SCNGeometry {
        makeGeometry(scores: scores, girthScale: 1.0, heightScale: 1.0)
    }

    /// Build an SCNGeometry with per-vertex scaling baked in.
    ///
    /// Non-uniform node-level scaling stretches the head along with the torso,
    /// which makes tall-thin and short-wide profiles look wrong. Instead we
    /// scale per vertex and smoothly blend toward a uniform scale above the
    /// neck so the head stays proportionally correct regardless of stature/BMI.
    func makeGeometry(scores: [Float], girthScale: Float, heightScale: Float) -> SCNGeometry {
        var verts = vertices(scores: scores)

        if girthScale != 1 || heightScale != 1 {
            var minY: Float =  .infinity
            var maxY: Float = -.infinity
            for i in 0..<vertCount {
                let y = verts[i * 3 + 1]
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
            let range = max(maxY - minY, 0.0001)
            // Neck-to-head-top blend band in normalized body height.
            // Below neckT: full body scaling. Above headT: scale the head only
            // by stature (heightScale), so BMI / girth changes don't distort
            // facial proportions. Wide blend so the transition is invisible.
            let neckT: Float = 0.78
            let headT: Float = 0.88
            // Head scales only with stature, and only partially so that very
            // tall users don't get comically large heads. Clamp to a sensible
            // range so extreme inputs can't break facial proportions.
            let headFactor: Float = 0.5 + 0.5 * heightScale
            let uniform = min(max(headFactor, 0.92), 1.08)

            for i in 0..<vertCount {
                let x = verts[i * 3 + 0]
                let y = verts[i * 3 + 1]
                let z = verts[i * 3 + 2]

                let t = (y - minY) / range
                let raw = (t - neckT) / (headT - neckT)
                let clamped = min(max(raw, 0), 1)
                let s = clamped * clamped * (3 - 2 * clamped)

                let sx = girthScale + (uniform - girthScale) * s
                let sy = heightScale + (uniform - heightScale) * s
                let sz = girthScale + (uniform - girthScale) * s

                verts[i * 3 + 0] = x * sx
                verts[i * 3 + 1] = y * sy
                verts[i * 3 + 2] = z * sz
            }
        }

        let normals = computeNormals(verts: verts)

        let vertData = verts.withUnsafeBufferPointer { Data(buffer: $0) }
        let normalData = normals.withUnsafeBufferPointer { Data(buffer: $0) }

        let vertSource = SCNGeometrySource(
            data: vertData,
            semantic: .vertex,
            vectorCount: vertCount,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: 3 * MemoryLayout<Float>.size
        )
        let normalSource = SCNGeometrySource(
            data: normalData,
            semantic: .normal,
            vectorCount: vertCount,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: 3 * MemoryLayout<Float>.size
        )
        let element = SCNGeometryElement(
            data: faces,
            primitiveType: .triangles,
            primitiveCount: faceCount,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        return SCNGeometry(sources: [vertSource, normalSource], elements: [element])
    }

    private func computeNormals(verts: [Float]) -> [Float] {
        var normals = [Float](repeating: 0, count: vertCount * 3)
        faces.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let idx = raw.bindMemory(to: UInt32.self)
            for f in 0..<faceCount {
                let i0 = Int(idx[f*3 + 0])
                let i1 = Int(idx[f*3 + 1])
                let i2 = Int(idx[f*3 + 2])
                let ax = verts[i0*3+0], ay = verts[i0*3+1], az = verts[i0*3+2]
                let bx = verts[i1*3+0], by = verts[i1*3+1], bz = verts[i1*3+2]
                let cx = verts[i2*3+0], cy = verts[i2*3+1], cz = verts[i2*3+2]
                let ux = bx-ax, uy = by-ay, uz = bz-az
                let vx = cx-ax, vy = cy-ay, vz = cz-az
                // cross(u, v)
                let nx = uy*vz - uz*vy
                let ny = uz*vx - ux*vz
                let nz = ux*vy - uy*vx
                normals[i0*3+0] += nx; normals[i0*3+1] += ny; normals[i0*3+2] += nz
                normals[i1*3+0] += nx; normals[i1*3+1] += ny; normals[i1*3+2] += nz
                normals[i2*3+0] += nx; normals[i2*3+1] += ny; normals[i2*3+2] += nz
            }
        }
        for v in 0..<vertCount {
            let x = normals[v*3+0], y = normals[v*3+1], z = normals[v*3+2]
            let len = (x*x + y*y + z*z).squareRoot()
            if len > 0 {
                normals[v*3+0] = x/len
                normals[v*3+1] = y/len
                normals[v*3+2] = z/len
            }
        }
        return normals
    }
}

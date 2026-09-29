#!/usr/bin/env python3
"""Pack HumanShape (CAESAR-norm-WSX) PCA basis into a compact binary for iOS.

Source data layout (Pishchulin et al. 2015, BSD non-commercial):
  meanShape.mat : points (6449, 3) — mean mesh in millimeters
                  CAESAR axes are X=left/right, Y=front/back, Z=up
  evectors.mat  : evectors (4300, 19347) — each row reshapes to (6449, 3)
  evalues.mat   : evalues (1, 4300) — eigenvalues (variances)
  model.dat     : ASCII; line 1 header "V F ? ?", lines 2..V+1 vertex
                  records, line V+2 separator, lines V+3..V+F+2 triangles "i j k"
                  (zero-indexed).

Output (little-endian, packed):
  uint32 vertCount
  uint32 faceCount
  uint32 kComponents
  float32 mean[V * 3]                     (meters, SceneKit axes)
  float32 basis[K * V * 3]                (pre-scaled by sqrt(evalue), meters)
  uint32  faces[F * 3]
"""

from pathlib import Path
import struct
import numpy as np
import scipy.io as sio

SRC = Path("/Users/rohangandotra/Desktop/APP/caesar-norm-wsx")
DST = Path("/Users/rohangandotra/Desktop/APP/AptoSwasthy/Sources/AptoSwasthy/Resources/body_basis.bin")
K_COMPONENTS = 50

def caesar_to_scenekit(arr_mm):
    # arr_mm: (..., 3) with CAESAR (x_lr, y_fb, z_up) in mm
    # return meters with SceneKit (x_lr, y_up, z_fb_negated)
    out = np.empty_like(arr_mm, dtype=np.float32)
    out[..., 0] =  arr_mm[..., 0] / 1000.0
    out[..., 1] =  arr_mm[..., 2] / 1000.0
    out[..., 2] = -arr_mm[..., 1] / 1000.0
    return out

def parse_faces(model_dat: Path, vert_count: int, face_count: int):
    # Structure: line 1 header, lines 2..V+1 vertex records, then F lines of
    # "i j k" triangles, followed by skeleton/joint metadata.
    faces = np.empty((face_count, 3), dtype=np.uint32)
    with model_dat.open() as fh:
        fh.readline()  # header
        for _ in range(vert_count):
            fh.readline()
        for i in range(face_count):
            parts = fh.readline().split()
            faces[i, 0] = int(parts[0])
            faces[i, 1] = int(parts[1])
            faces[i, 2] = int(parts[2])
    return faces

def main():
    print("Loading meanShape …")
    mean_mm = sio.loadmat(SRC / "meanShape.mat")["points"].astype(np.float64)
    V = mean_mm.shape[0]
    print(f"  V = {V}")

    print("Loading evectors (this is 640MB, takes a moment) …")
    evectors = sio.loadmat(SRC / "evectors.mat")["evectors"].astype(np.float64)
    print(f"  evectors shape = {evectors.shape}")

    print("Loading evalues …")
    evalues = sio.loadmat(SRC / "evalues.mat")["evalues"].astype(np.float64).ravel()
    print(f"  evalues count = {evalues.size}, top5 = {evalues[:5]}")

    # Header parse
    header = (SRC / "model.dat").read_text().splitlines()[0].split()
    F = int(header[1])
    print(f"  F = {F}")
    print("Parsing faces from model.dat …")
    faces = parse_faces(SRC / "model.dat", V, F)
    print(f"  faces range: {faces.min()} … {faces.max()}")

    K = min(K_COMPONENTS, evectors.shape[0])
    print(f"Selecting top K = {K} components")

    mean_sk = caesar_to_scenekit(mean_mm)  # (V, 3) float32

    # Center mean horizontally + vertically (so model sits at origin), keep height span
    centroid_xy = mean_sk[:, [0, 2]].mean(axis=0)
    mean_sk[:, 0] -= centroid_xy[0]
    mean_sk[:, 2] -= centroid_xy[1]
    # Drop floor to y=0
    mean_sk[:, 1] -= mean_sk[:, 1].min()

    # Basis: each component (K, V, 3) in scenekit meters, pre-scaled by sqrt(evalue).
    # MATLAB stores M(:) in column-major order, so a flattened (V,3) deformation
    # is laid out as [x1..xV, y1..yV, z1..zV]. Reshape via (3,V).T to recover (V,3).
    print("Building basis …")
    basis = np.empty((K, V, 3), dtype=np.float32)
    for i in range(K):
        comp_mm = evectors[i].reshape(3, V).T
        comp_sk = caesar_to_scenekit(comp_mm)        # / 1000 + axis swap
        basis[i] = comp_sk * float(np.sqrt(evalues[i]))

    DST.parent.mkdir(parents=True, exist_ok=True)
    print(f"Writing {DST} …")
    with DST.open("wb") as fh:
        fh.write(struct.pack("<III", V, F, K))
        fh.write(mean_sk.astype(np.float32).tobytes())
        fh.write(basis.astype(np.float32).tobytes())
        fh.write(faces.astype(np.uint32).tobytes())

    size_mb = DST.stat().st_size / (1024 * 1024)
    print(f"Done. {DST.name} = {size_mb:.2f} MB")

if __name__ == "__main__":
    main()

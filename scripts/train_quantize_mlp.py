#!/usr/bin/env python3
"""
scripts/train_quantize_mlp.py
Project: 50-Day Tensor Edge Accelerator (Day 4 - Friend B / Embedded & DSP)
Description:
  1. Trains a 3-layer MLP (16 inputs -> 32 hidden -> 16 hidden -> 1 output) on 
     bearing vibration spectral features (16 FFT energy bins).
  2. Evaluates floating-point accuracy (>95% on anomaly detection).
  3. Quantizes all floating-point weights and biases to INT8 symmetric format:
     Scale S = max(|W|) / 127
     Q = clamp(round(W / S), -128, +127)
  4. Formats and exports INT8 weight matrices into 4x4 tiled .hex files 
     matching Friend A's 4x4 Systolic Array architecture.
"""

import os
import numpy as np

def generate_vibration_features(n_samples=2000, seed=42):
    np.random.seed(seed)
    # 16 spectral bins representing vibration frequencies
    # Normal: energy concentrated in bins 0-3 (low frequencies, smooth rotation)
    # Anomaly: high energy spikes in bins 6-12 (harmonic fault peaks from cracked race)
    X = np.zeros((n_samples, 16), dtype=np.float32)
    y = np.zeros(n_samples, dtype=np.float32)

    half = n_samples // 2
    # Healthy samples (class 0)
    for i in range(half):
        base = np.random.exponential(scale=0.15, size=16)
        base[0:4] += np.random.uniform(0.4, 0.9, size=4)
        X[i] = base / np.max(base)
        y[i] = 0.0

    # Faulty samples (class 1)
    for i in range(half, n_samples):
        base = np.random.exponential(scale=0.15, size=16)
        base[6:12] += np.random.uniform(0.7, 1.4, size=6)
        base[1:3] += np.random.uniform(0.2, 0.5, size=2)
        X[i] = base / np.max(base)
        y[i] = 1.0

    indices = np.random.permutation(n_samples)
    return X[indices], y[indices]

class TinyMLP:
    def __init__(self, in_dim=16, h1=32, h2=16, out_dim=1):
        np.random.seed(1337)
        # Xavier initialization
        self.W1 = np.random.randn(in_dim, h1).astype(np.float32) * np.sqrt(2.0 / in_dim)
        self.b1 = np.zeros(h1, dtype=np.float32)

        self.W2 = np.random.randn(h1, h2).astype(np.float32) * np.sqrt(2.0 / h1)
        self.b2 = np.zeros(h2, dtype=np.float32)

        self.W3 = np.random.randn(h2, out_dim).astype(np.float32) * np.sqrt(2.0 / h2)
        self.b3 = np.zeros(out_dim, dtype=np.float32)

    def relu(self, x):
        return np.maximum(0.0, x)

    def sigmoid(self, x):
        return 1.0 / (1.0 + np.exp(-np.clip(x, -15.0, 15.0)))

    def forward(self, X):
        self.z1 = np.dot(X, self.W1) + self.b1
        self.a1 = self.relu(self.z1)

        self.z2 = np.dot(self.a1, self.W2) + self.b2
        self.a2 = self.relu(self.z2)

        self.z3 = np.dot(self.a2, self.W3) + self.b3
        self.out = self.sigmoid(self.z3)
        return self.out

    def train(self, X, y, epochs=150, lr=0.03):
        m = len(X)
        y = y.reshape(-1, 1)
        for ep in range(epochs):
            pred = self.forward(X)
            loss = -np.mean(y * np.log(pred + 1e-8) + (1.0 - y) * np.log(1.0 - pred + 1e-8))

            # Backpropagation
            d_out = (pred - y) / m

            dW3 = np.dot(self.a2.T, d_out)
            db3 = np.sum(d_out, axis=0)

            da2 = np.dot(d_out, self.W3.T)
            dz2 = da2 * (self.z2 > 0)
            dW2 = np.dot(self.a1.T, dz2)
            db2 = np.sum(dz2, axis=0)

            da1 = np.dot(dz2, self.W2.T)
            dz1 = da1 * (self.z1 > 0)
            dW1 = np.dot(X.T, dz1)
            db1 = np.sum(dz1, axis=0)

            self.W3 -= lr * dW3
            self.b3 -= lr * db3
            self.W2 -= lr * dW2
            self.b2 -= lr * db2
            self.W1 -= lr * dW1
            self.b1 -= lr * db1

            if (ep + 1) % 30 == 0 or ep == epochs - 1:
                preds_binary = (pred >= 0.5).astype(np.float32)
                acc = np.mean(preds_binary == y) * 100.0
                print(f"  [Epoch {ep+1:3d}/{epochs}] Loss: {loss:.4f} | Accuracy: {acc:.2f}%")

def quantize_symmetric_int8(matrix):
    """
    Symmetric INT8 quantization mapping range [-max_abs, +max_abs] to [-127, +127].
    Returns quantized matrix (int8), scale factor S (float), and max quantization error.
    """
    max_val = np.max(np.abs(matrix))
    if max_val == 0:
        return np.zeros_like(matrix, dtype=np.int8), 1.0, 0.0

    scale = max_val / 127.0
    quantized = np.round(matrix / scale)
    quantized = np.clip(quantized, -128, 127).astype(np.int8)

    # Dequantize to calculate SQNR & error
    dequantized = quantized.astype(np.float32) * scale
    error = np.max(np.abs(matrix - dequantized))
    return quantized, scale, error

def export_4x4_tiled_hex(weight_matrix, output_path):
    """
    Packs a weight matrix (rows, cols) into 4x4 tiles suitable for Friend A's systolic array.
    Each line in .hex contains 4 bytes (32-bit row slice in 2-digit hex).
    """
    rows, cols = weight_matrix.shape
    # Pad to multiple of 4
    pad_r = (4 - (rows % 4)) % 4
    pad_c = (4 - (cols % 4)) % 4
    padded = np.pad(weight_matrix, ((0, pad_r), (0, pad_c)), mode='constant', constant_values=0)

    p_rows, p_cols = padded.shape
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    with open(output_path, "w") as f:
        # Tile into 4x4 sub-matrices
        for tr in range(0, p_rows, 4):
            for tc in range(0, p_cols, 4):
                f.write(f"// Tile ({tr//4},{tc//4}) - 4x4 Block\n")
                for r in range(4):
                    row_vals = padded[tr + r, tc:tc+4]
                    # Pack 4 INT8s into 32-bit hex (Col3, Col2, Col1, Col0)
                    hex_str = "".join(f"{(int(v) & 0xFF):02X}" for v in reversed(row_vals))
                    f.write(f"{hex_str}\n")

    print(f"  Exported: {output_path} ({p_rows}x{p_cols} tiled into {p_rows//4 * p_cols//4} blocks of 4x4)")

def main():
    print("==================================================================")
    print("  FRIEND B (DAY 4): Edge MLP Training & INT8 Quantization Engine  ")
    print("==================================================================")

    # 1. Dataset Generation
    print("[1] Generating 2,000 bearing vibration feature vectors (16 spectral bins)...")
    X, y = generate_vibration_features(n_samples=2000)
    split = 1600
    X_train, y_train = X[:split], y[:split]
    X_test, y_test   = X[split:], y[split:]

    # 2. Train Float32 Model
    print("[2] Training 3-Layer MLP (16 -> 32 -> 16 -> 1) with ReLU...")
    mlp = TinyMLP(in_dim=16, h1=32, h2=16, out_dim=1)
    mlp.train(X_train, y_train, epochs=150, lr=0.04)

    # Test Accuracy
    test_preds = mlp.forward(X_test)
    test_acc = np.mean((test_preds >= 0.5) == y_test.reshape(-1, 1)) * 100.0
    print(f"[3] Floating-Point Test Accuracy: {test_acc:.2f}%")

    # 3. Quantize Weights to INT8
    print("[4] Performing Symmetric INT8 Quantization (Scale S = max|W| / 127)...")
    qW1, sW1, err1 = quantize_symmetric_int8(mlp.W1)
    qW2, sW2, err2 = quantize_symmetric_int8(mlp.W2)
    qW3, sW3, err3 = quantize_symmetric_int8(mlp.W3)

    print(f"  Layer 1 (16x32): Scale S1={sW1:.6f}, Max Quant Error={err1:.6f}")
    print(f"  Layer 2 (32x16): Scale S2={sW2:.6f}, Max Quant Error={err2:.6f}")
    print(f"  Layer 3 (16x1) : Scale S3={sW3:.6f}, Max Quant Error={err3:.6f}")

    # 4. Export to Friend A's 4x4 Systolic Array .hex format
    print("[5] Exporting INT8 Weights into 4x4 Tiled .hex files for FPGA Array...")
    export_4x4_tiled_hex(qW1, "sim/weights_layer1.hex")
    export_4x4_tiled_hex(qW2, "sim/weights_layer2.hex")
    export_4x4_tiled_hex(qW3, "sim/weights_layer3.hex")

    print("==================================================================")
    print("  DAY 4 COMPLETE: INT8 Tiled Weights Ready for Systolic Co-Sim!   ")
    print("==================================================================")

if __name__ == "__main__":
    main()

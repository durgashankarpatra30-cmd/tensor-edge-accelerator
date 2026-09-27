"""
scripts/generate_vibration_dataset.py - Day 3 Python Feature Generator

Simulates real-world industrial bearing vibration datasets (NASA IMS / CWRU):
1. Generates 100 healthy bearing windows and 100 damaged bearing windows (outer-race fault).
2. Performs 128-point FFT spectral feature extraction.
3. Exports 16-element Q1.7 INT8 vectors into sim/input_features.hex for Friend A's Verilog testbenches.
"""

import os
import numpy as np

def generate_vibration_sample(is_fault: bool, num_samples: int = 128, fs: int = 1000) -> np.ndarray:
    """Generate 128-point vibration window at 1 kHz sample rate"""
    t = np.arange(num_samples) / fs
    # Baseline motor unbalance tone (30 Hz = 1800 RPM) + white noise
    signal = 0.3 * np.sin(2 * np.pi * 30 * t) + 0.1 * np.random.normal(0, 0.5, num_samples)

    if is_fault:
        # Outer-race bearing fault impact (BPFO = 120 Hz harmonics + periodic ringdown impacts)
        fault_tone = 0.6 * np.sin(2 * np.pi * 120 * t) + 0.4 * np.sin(2 * np.pi * 240 * t)
        signal += fault_tone

    # Normalize to signed INT8 Q1.7 [-128, +127]
    signal = np.clip(np.round(signal * 80), -128, 127).astype(np.int8)
    return signal

def extract_16_features(signal: np.ndarray) -> list[int]:
    """128-point FFT spectral energy pooling into 16 frequency bands"""
    # 128-point FFT
    fft_vals = np.fft.rfft(signal, n=128)  # 65 complex bins
    power = np.abs(fft_vals[1:65]) ** 2    # Skip DC bin 0

    # Pool 4 bins per band into 16 bands
    features = []
    for i in range(16):
        band_energy = np.sum(power[i*4 : (i+1)*4])
        features.append(band_energy)

    features = np.array(features)
    max_val = np.max(features) if np.max(features) > 0 else 1
    # Scale to 0..+127 in Q1.7
    quantized_features = np.clip(np.round((features / max_val) * 127), 0, 127).astype(np.int8)
    return [int(x) for x in quantized_features]

def main():
    os.makedirs("sim", exist_ok=True)
    hex_path = "sim/input_features.hex"

    print("[Dataset Generator] Simulating 200 NASA/CWRU Industrial Bearing Windows (1 kHz)...")
    with open(hex_path, "w") as f:
        # First 100: Healthy bearings (Fault = 0)
        for _ in range(100):
            sig = generate_vibration_sample(is_fault=False)
            feats = extract_16_features(sig)
            # Pack 16 INT8 values as 32-character hex line
            hex_str = "".join(f"{x & 0xFF:02X}" for x in feats)
            f.write(f"{hex_str} // Label: HEALTHY (0)\n")

        # Next 100: Damaged bearings (Fault = 1)
        for _ in range(100):
            sig = generate_vibration_sample(is_fault=True)
            feats = extract_16_features(sig)
            hex_str = "".join(f"{x & 0xFF:02X}" for x in feats)
            f.write(f"{hex_str} // Label: ANOMALY (1)\n")

    print(f"[Dataset Generator] Successfully generated 200 feature frames -> {hex_path}")
    print("[Dataset Generator] Ready to feed into 4x4 Systolic Array in Week 2!")

if __name__ == "__main__":
    main()

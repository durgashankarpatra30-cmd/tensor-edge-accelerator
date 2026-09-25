import os

def q17_mult(a: int, b: int) -> tuple[int, int]:
    """
    Bit-exact Q1.7 signed fixed-point multiplier matching rtl/q_mult.v
    Inputs:  a, b in [-128, +127]
    Outputs: (result_0 in [-128, +127], overflow in [0, 1])
    """
    full_product = a * b
    shifted_product = full_product >> 7  # Arithmetic right shift by 7

    if shifted_product > 127:
        return 127, 1
    elif shifted_product < -128:
        return -128, 1
    else:
        return shifted_product, 0


if __name__ == "__main__":
    os.makedirs("sim", exist_ok=True)
    hex_path = "sim/golden_vectors.hex"

    overflow_count = 0
    with open(hex_path, "w") as f:
        for a in range(-128, 128):
            for b in range(-128, 128):
                res, ovf = q17_mult(a, b)
                if ovf:
                    overflow_count += 1
                f.write(f"{a & 0xFF:02X}{b & 0xFF:02X}{res & 0xFF:02X}0{ovf:1X}\n")

    print(f"[Golden Model] Generated 65,536 vectors -> {hex_path}")
    print(f"[Golden Model] Total overflow cases found: {overflow_count} (at a=-128, b=-128)")

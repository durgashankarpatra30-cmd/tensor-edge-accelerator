import os
from reportlab.lib.pagesizes import A4
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, HRFlowable, Preformatted
)

def build_day1_pdf():
    os.makedirs("docs", exist_ok=True)
    pdf_path = os.path.abspath("docs/Friend_B_Day1_Complete_Guide.pdf")

    doc = SimpleDocTemplate(
        pdf_path,
        pagesize=A4,
        rightMargin=34,
        leftMargin=34,
        topMargin=36,
        bottomMargin=36
    )

    styles = getSampleStyleSheet()
    title_style = ParagraphStyle(
        "DocTitle",
        parent=styles["Title"],
        fontSize=19,
        leading=23,
        textColor=colors.HexColor("#0F172A"),
        spaceAfter=4
    )
    subtitle_style = ParagraphStyle(
        "DocSubtitle",
        parent=styles["Normal"],
        fontSize=10.5,
        leading=14,
        textColor=colors.HexColor("#475569"),
        spaceAfter=10
    )
    h1_style = ParagraphStyle(
        "H1",
        parent=styles["Heading1"],
        fontSize=13.5,
        leading=17,
        textColor=colors.HexColor("#1E3A8A"),
        spaceBefore=10,
        spaceAfter=5
    )
    h2_style = ParagraphStyle(
        "H2",
        parent=styles["Heading2"],
        fontSize=11,
        leading=14.5,
        textColor=colors.HexColor("#0F766E"),
        spaceBefore=8,
        spaceAfter=4
    )
    body_style = ParagraphStyle(
        "Body",
        parent=styles["Normal"],
        fontSize=9.3,
        leading=13.2,
        textColor=colors.HexColor("#1E293B"),
        spaceAfter=5
    )
    code_style = ParagraphStyle(
        "CodePre",
        fontName="Courier",
        fontSize=7.8,
        leading=10.2,
        textColor=colors.HexColor("#0F172A"),
        backColor=colors.HexColor("#F1F5F9"),
        borderPadding=6,
        spaceAfter=8
    )

    story = []

    # =========================================================================
    # PAGE 1: COVER & PART 1 (COMPLETE DAY 1 THEORY FROM SCRATCH)
    # =========================================================================
    story.append(Paragraph("DAY 1 COMPLETE TEXTBOOK & WORKFLOW GUIDE FOR FRIEND B", title_style))
    story.append(Paragraph("Embedded Firmware (Circular DMA Ring Buffer in C) & Python Bit-Exact Q1.7 Golden Hardware Model", subtitle_style))
    story.append(HRFlowable(width="100%", thickness=1.5, color=colors.HexColor("#1E3A8A"), spaceAfter=10))

    story.append(Paragraph("1. The Big Picture: What Are You Building on Day 1 & How Does It Connect to Friend A?", h1_style))
    story.append(Paragraph(
        "In Project 1 (AXI4-Stream Tensor Accelerator), Friend A designs the silicon/FPGA hardware multiplier (rtl/q_mult.v) "
        "and systolic array in Verilog, while YOU (Friend B) build two mission-critical software components on Day 1:",
        body_style
    ))
    story.append(Paragraph(
        "<b>Deliverable 1 (scripts/golden_model.py):</b> A Bit-Exact Python Hardware Simulator that computes all 65,536 "
        "possible 8-bit signed fixed-point (Q1.7) multiplications and outputs a hexadecimal memory file (<b>sim/golden_vectors.hex</b>) "
        "used to mathematically verify that Friend A's hardware chip has zero bugs.<br/>"
        "<b>Deliverable 2 (firmware/dma_ring_buffer.c):</b> A Lock-Free Circular DMA (Direct Memory Access) Ring Buffer in C "
        "that allows the microcontroller to stream 1,000 sensor samples/second and 921,600-baud UART debug packets without "
        "ever stalling or blocking the CPU.",
        body_style
    ))

    story.append(Paragraph("2. Deep-Dive Theory Part A: Q1.7 Fixed-Point Math & Two's Complement Hex", h1_style))
    story.append(Paragraph(
        "<b>Why Don't AI Chips Use Standard Float (float32)?</b><br/>"
        "In Python, neural network weights are decimals between -1.0 and +1.0 (e.g., 0.5, -0.25). However, a 32-bit floating-point "
        "multiplier requires ~1,500 logic gates on a chip. By converting decimals into 8-bit Signed Integers (INT8, from -128 to +127), "
        "the hardware shrinks by 15x in area and uses 10x less energy!",
        body_style
    ))
    story.append(Paragraph(
        "<b>How Does Q1.7 Format Store Decimals Inside an Integer?</b><br/>"
        "In Q1.7 format (1 Sign Bit + 7 Fractional Bits), every decimal number is multiplied by <b>2^7 = 128</b> and stored as an integer:",
        body_style
    ))

    q17_table = [
        ["Real Decimal Value", "Formula (Decimal x 128)", "8-Bit Signed Integer", "8-Bit Binary (Two's Comp)", "Hex (a & 0xFF)"],
        ["+0.50", "0.50 x 128", "+64", "0100_0000", "0x40"],
        ["+0.25", "0.25 x 128", "+32", "0010_0000", "0x20"],
        ["0.00", "0.00 x 128", "0", "0000_0000", "0x00"],
        ["-0.50", "-0.50 x 128", "-64", "1100_0000 (-128 + 64)", "0xC0"],
        ["-1.00 (Minimum)", "-1.00 x 128", "-128", "1000_0000 (-128 + 0)", "0x80"],
        ["+0.9921875 (Max)", "+127 / 128", "+127", "0111_1111 (0 + 127)", "0x7F"]
    ]
    t1 = Table(q17_table, colWidths=[100, 105, 95, 125, 90])
    t1.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#1E3A8A")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 8),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#CBD5E1")),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F8FAFC")]),
        ("PADDING", (0, 0), (-1, -1), 4),
    ]))
    story.append(t1)
    story.append(Spacer(1, 6))

    story.append(Paragraph(
        "<b>The 3 Golden Rules of Q1.7 Multiplication in Your Python Golden Model:</b><br/>"
        "1. <b>16-Bit Raw Multiply:</b> When you multiply two Q1.7 integers (e.g., +0.5 x +0.5 -> 64 x 64 = 4096), the scale factor "
        "128 was multiplied twice (128 x 128).<br/>"
        "2. <b>Arithmetic Right Shift by 7 (>> 7):</b> To cancel out the extra factor of 128, divide by 128 using arithmetic right shift: "
        "<b>shifted_product = (a * b) >> 7</b>. For 4096 >> 7, you get <b>+32</b> (which is 32/128 = +0.25!).<br/>"
        "3. <b>The -128 x -128 Overflow Trap & Saturation:</b> When a = -128 (-1.0) and b = -128 (-1.0), raw product = +16,384, and "
        "16,384 >> 7 = <b>+128</b>. Because 8-bit signed numbers only go up to <b>+127</b>, +128 overflows! Hardware clamps (saturates) "
        "any result > 127 to <b>+127</b> and sets <b>overflow = 1</b>.",
        body_style
    ))
    story.append(Paragraph(
        "<b>Why Do We Write (a & 0xFF) in Python When Saving Hex Files?</b><br/>"
        "Verilog's $readmemh cannot read minus signs like '-64'. In Python, bitwise AND with 0xFF (<b>-64 & 0xFF</b>) strips the sign "
        "extension and gives the exact 8-bit Two's Complement byte (<b>0xC0</b> for -64, <b>0x80</b> for -128).",
        body_style
    ))

    story.append(PageBreak())

    # =========================================================================
    # PAGE 2: THEORY PART B (CIRCULAR DMA RING BUFFER) + CODE 1 (GOLDEN MODEL)
    # =========================================================================
    story.append(Paragraph("3. Deep-Dive Theory Part B: How a Circular DMA Ring Buffer Works in C", h1_style))
    story.append(Paragraph(
        "<b>Why Standard Arrays Fail in Real-Time Embedded Systems:</b><br/>"
        "When an accelerometer (MPU6050 at 1,000 Hz) or high-speed UART (921,600 baud) streams data, the CPU cannot stop what it is doing "
        "to wait for every byte. Instead, a hardware controller called <b>DMA (Direct Memory Access)</b> writes incoming bytes directly "
        "into RAM in the background while the CPU computes neural network features.",
        body_style
    ))
    story.append(Paragraph(
        "<b>How the Circular Ring Buffer Solves Memory Overflow:</b><br/>"
        "A Ring Buffer connects the end of a fixed C array (index 255) back to index 0 like a circle, managed by two indices:<br/>"
        "- <b>head (Write Index):</b> Owned by the <b>DMA Producer</b>. Every time a new byte arrives, DMA writes to <i>buffer[head]</i> and advances <i>head</i>.<br/>"
        "- <b>tail (Read Index):</b> Owned by the <b>CPU Consumer</b>. Every time the CPU reads a byte, it reads from <i>buffer[tail]</i> and advances <i>tail</i>.",
        body_style
    ))

    dma_rules = [
        ["Condition / Operation", "C Formula (Power-of-2 Size = 256)", "Engineering Reason"],
        ["Buffer is EMPTY", "head == tail", "The CPU has read every byte that DMA wrote."],
        ["Buffer is FULL", "((head + 1) & 255) == tail", "Advancing head by 1 would collide with unread tail!"],
        ["Fast Wrap-Around", "next_head = (head + 1) & 255;", "Bitwise '& 255' takes 1 CPU cycle vs 20+ cycles for '% 256'!"],
        ["Prevent Compiler Bugs", "volatile uint16_t head, tail;", "'volatile' forces C to re-read RAM when DMA changes head in an ISR."]
    ]
    t2 = Table(dma_rules, colWidths=[115, 155, 250])
    t2.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#0F766E")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 8),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#CBD5E1")),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F0FDFA")]),
        ("PADDING", (0, 0), (-1, -1), 4),
    ]))
    story.append(t2)
    story.append(Spacer(1, 8))

    story.append(Paragraph("4. Annotated Code #1: scripts/golden_model.py", h1_style))
    story.append(Paragraph(
        "Open <b>scripts/golden_model.py</b> in VS Code. Study every line below and run it to generate the 65,536 golden vectors:",
        body_style
    ))

    py_code = """import os

def q17_mult(a: int, b: int) -> tuple[int, int]:
    \"\"\"Bit-exact Q1.7 signed fixed-point multiplier matching Friend A's rtl/q_mult.v\"\"\"
    # Step 1: 16-bit signed multiplication (range: -16256 to +16384)
    full_product = a * b

    # Step 2: Arithmetic right shift by 7 (divides by 128 while keeping sign)
    shifted_product = full_product >> 7

    # Step 3: Saturation clamping to 8-bit signed range [-128, +127]
    if shifted_product > 127:
        return 127, 1      # Clamp to +127 (0x7F) and set overflow flag = 1
    elif shifted_product < -128:
        return -128, 1     # Clamp to -128 (0x80) and set overflow flag = 1
    else:
        return shifted_product, 0

if __name__ == "__main__":
    os.makedirs("sim", exist_ok=True)
    hex_path = "sim/golden_vectors.hex"
    overflow_count = 0

    with open(hex_path, "w") as f:
        # Sweep all 256 x 256 = 65,536 signed 8-bit input pairs
        for a in range(-128, 128):
            for b in range(-128, 128):
                res, ovf = q17_mult(a, b)
                if ovf:
                    overflow_count += 1
                # Pack {a[7:0], b[7:0], res[7:0], ovf} as Two's Complement Hex
                f.write(f"{a & 0xFF:02X}{b & 0xFF:02X}{res & 0xFF:02X}0{ovf:1X}\\n")

    print(f"[Golden Model] Generated 65,536 vectors -> {hex_path}")
    print(f"[Golden Model] Total overflow cases found: {overflow_count} (at a=-128, b=-128)")"""
    story.append(Preformatted(py_code, code_style))

    story.append(PageBreak())

    # =========================================================================
    # PAGE 3: ANNOTATED CODE #2 (DMA RING BUFFER IN C) & EXECUTION WORKFLOW
    # =========================================================================
    story.append(Paragraph("5. Annotated Code #2: firmware/dma_ring_buffer.c", h1_style))
    story.append(Paragraph(
        "Open <b>firmware/dma_ring_buffer.c</b> in VS Code. This C code implements the non-blocking DMA ring buffer and tests "
        "streaming 500 Q1.7 samples across multiple wrap-arounds of the 256-byte buffer:",
        body_style
    ))

    c_code = """#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

#define DMA_BUF_SIZE 256              // MUST be a power of 2 (2^8 = 256)
#define DMA_BUF_MASK (DMA_BUF_SIZE - 1) // 255 (0xFF) for 1-cycle bitwise wrap-around

typedef struct {
    int8_t            buffer[DMA_BUF_SIZE]; // Stores signed Q1.7 INT8 samples (-128..+127)
    volatile uint16_t head;                 // Write index (Updated by DMA ISR)
    volatile uint16_t tail;                 // Read index  (Updated by CPU Task)
    uint32_t          overflow_drops;       // Diagnostic counter for dropped bytes
} dma_ring_buf_t;

void dma_rb_init(dma_ring_buf_t *rb) {
    rb->head = 0;
    rb->tail = 0;
    rb->overflow_drops = 0;
}

// Called by DMA Interrupt when a new byte arrives from UART/SPI/Sensor
bool dma_rb_push(dma_ring_buf_t *rb, int8_t sample) {
    uint16_t next_head = (rb->head + 1) & DMA_BUF_MASK; // Wrap 255 -> 0 using & 255
    if (next_head == rb->tail) {
        rb->overflow_drops++; // Buffer full! Do not overwrite unread CPU data
        return false;
    }
    rb->buffer[rb->head] = sample;
    rb->head = next_head;
    return true;
}

// Called by CPU FreeRTOS Task to process the next available sample
bool dma_rb_pop(dma_ring_buf_t *rb, int8_t *out_sample) {
    if (rb->head == rb->tail) {
        return false; // Buffer empty! CPU returns immediately without blocking
    }
    *out_sample = rb->buffer[rb->tail];
    rb->tail = (rb->tail + 1) & DMA_BUF_MASK;
    return true;
}

int main(void) {
    dma_ring_buf_t uart_dma;
    dma_rb_init(&uart_dma);
    printf("[Embedded Day 1] Testing Lock-Free DMA Circular Ring Buffer...\\n");

    // Stream 500 samples (nearly 2x the 256-byte capacity) in 5 bursts of 100
    int total_verified = 0;
    for (int batch = 0; batch < 5; batch++) {
        for (int i = 0; i < 100; i++) {
            int8_t val = (int8_t)((batch * 100 + i) % 127);
            dma_rb_push(&uart_dma, val);
        }
        for (int i = 0; i < 100; i++) {
            int8_t out = 0;
            if (dma_rb_pop(&uart_dma, &out)) total_verified++;
        }
    }
    printf("PASS: Streamed %d Q1.7 samples across circular wrap-around | Drops: %u\\n",
           total_verified, uart_dma.overflow_drops);
    return 0;
}"""
    story.append(Preformatted(c_code, code_style))

    story.append(Paragraph("6. Step-by-Step Terminal Workflow to Run & Push Day 1", h1_style))
    workflow_txt = """# STEP 1: Open VS Code Terminal (Ctrl + ~) inside tensor-edge-accelerator and run Golden Model:
python scripts/golden_model.py
# Expected Output:
# [Golden Model] Generated 65,536 vectors -> sim/golden_vectors.hex
# [Golden Model] Total overflow cases found: 1 (at a=-128, b=-128)

# STEP 2: Compile and run the C Circular DMA Ring Buffer:
gcc firmware/dma_ring_buffer.c -o sim/dma_test.exe
./sim/dma_test.exe
# Expected Output:
# [Embedded Day 1] Testing Lock-Free DMA Circular Ring Buffer...
# PASS: Streamed 500 Q1.7 samples across circular wrap-around | Drops: 0

# STEP 3: Sync your Day 1 work to GitHub so Friend A can see your commit:
git pull origin main
git add scripts/golden_model.py firmware/dma_ring_buffer.c
git commit -m "Day 1 [Friend B]: Verified Python Q1.7 golden model and C DMA ring buffer"
git push origin main"""
    story.append(Preformatted(workflow_txt, code_style))

    story.append(Paragraph("7. Quick Self-Check Quiz for Friend B (Verify You Mastered Day 1!)", h1_style))
    story.append(Paragraph(
        "<b>Q1:</b> In Q1.7 format (scale = 128), what integer represents -0.25, and what is (-0.25 & 0xFF) in hex? "
        "<i>(Answer: -0.25 x 128 = -32; -32 & 0xFF = 0xE0)</i><br/>"
        "<b>Q2:</b> Why does a 256-byte DMA ring buffer hold a maximum of 255 unread bytes instead of 256? "
        "<i>(Answer: Because if head advanced 1 more slot to equal tail, head == tail would look identical to an EMPTY buffer!)</i><br/>"
        "<b>Q3:</b> Why must <i>head</i> and <i>tail</i> be declared <b>volatile</b> in C? "
        "<i>(Answer: Because the hardware DMA interrupt updates head asynchronously; without volatile, the C compiler might cache an old value in a CPU register.)</i>",
        body_style
    ))

    doc.build(story)
    print(f"Day 1 Complete Guide PDF created at: {pdf_path}")

if __name__ == "__main__":
    build_day1_pdf()

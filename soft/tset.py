#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Read a 1024×8-bit signed COE file, plot the time-domain waveform,
compute a 1024-point FFT, and export real / imag components + magnitude.

Author: you
"""

from pathlib import Path
import re
import numpy as np
import matplotlib.pyplot as plt

# ====== 修改成你的 .coe 路径 ======
COE_PATH = Path(r"E:/gameproject/project1/waveform_C_15kSin_25kTri_radix16.coe")
# =================================


def parse_coe_signed(fname: Path) -> np.ndarray:
    """读取 8-bit 两补码 COE → float32[1024]"""
    text = fname.read_text().lower()

    # 1) 提取进制
    radix = int(re.search(r"memory_initialization_radix\s*=\s*(\d+)\s*;",
                          text).group(1))

    # 2) 提取并切分数据区
    vec = re.split(r"memory_initialization_vector\s*=", text, 1)[1]
    tokens = re.split(r"[\s,;]+", vec.strip())[:-1]          # 去掉末尾空串

    # 3) 按进制转 uint8，再视图为 int8（两补码 → 有符号）
    uint8_data = np.fromiter((int(tk, radix) for tk in tokens), dtype=np.uint8,
                             count=len(tokens))
    if uint8_data.size != 1024:
        raise ValueError(f"应为 1024 点，实际 {uint8_data.size}")

    int8_data = uint8_data.view(np.int8).astype(np.float32)   # -128 ~ 127
    return int8_data


def main():
    if not COE_PATH.is_file():
        raise FileNotFoundError(f"找不到 COE 文件: {COE_PATH}")

    signal = parse_coe_signed(COE_PATH)

    # -------- 时域波形 --------
    plt.figure(figsize=(8, 3))
    plt.plot(signal, lw=0.8)
    plt.title("Time-domain waveform (signed 8-bit)")
    plt.xlabel("Sample index")
    plt.ylabel("Amplitude")
    plt.grid(True)

    # -------- 1024-点 FFT -------
    fft_complex = np.fft.fft(signal, n=1024)
    fft_mag = np.abs(fft_complex) / 1024.0
    fft_amp = np.sqrt(fft_complex.real**2 + fft_complex.imag**2)

    freqs = np.arange(512)

    plt.figure(figsize=(8, 3))
    plt.stem(freqs, fft_mag[:512], basefmt=" ")
    plt.title("FFT magnitude (0-0.5 Fs)")
    plt.xlabel("Frequency bin")
    plt.ylabel("|X[k]|")
    plt.grid(True)

    # ----- 导出结果 -----
    np.save("fft_complex.npy", fft_complex.astype(np.complex64))
    np.savetxt("fft_real.csv", fft_complex.real,  delimiter=",", fmt="%.6f")
    np.savetxt("fft_imag.csv", fft_complex.imag,  delimiter=",", fmt="%.6f")
    np.savetxt("fft_amplitude.csv", fft_amp, delimiter=",", fmt="%.6f")
    print("✔ fft_complex.npy / fft_real.csv / fft_imag.csv / fft_amplitude.csv 已生成")

    plt.tight_layout()
    plt.show()


if __name__ == "__main__":
    main()

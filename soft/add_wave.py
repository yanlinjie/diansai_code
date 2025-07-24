import numpy as np
from pathlib import Path

# ========== 用户配置 ==========
FS = 1_000_000            # 采样率 1 MHz
DEPTH = 1024              # 样本点数
AMPLITUDE = 127           # 8 bit 有符号最大振幅 ±127
OUT_BASE = "waveform_C"   # 输出文件名前缀
# ========== 三种 → 四种测试场景 ==========
CASES = [
    # 1) sine + sine：50 kHz & 100 kHz
    dict(A=dict(type="sine",  freq=50_000),
         B=dict(type="sine",  freq=100_000),
         tag="50k_100k"),

    # 2) sine + sine：30 kHz & 40 kHz（10 kHz 整数倍）
    dict(A=dict(type="sine",  freq=30_000),
         B=dict(type="sine",  freq=40_000),
         tag="30k_40k"),

    # 3) sine + triangle：15 kHz & 25 kHz（5 kHz 整数倍）
    dict(A=dict(type="sine",     freq=15_000),
         B=dict(type="triangle", freq=25_000),
         tag="15kSin_25kTri"),

    # 4) triangle + triangle：20 kHz & 35 kHz（5 kHz 整数倍）★ 新增
    dict(A=dict(type="triangle", freq=20_000),
         B=dict(type="triangle", freq=35_000),
         tag="20kTri_35kTri"),
]
# =======================================



def _base_wave(wtype: str, t: np.ndarray):
    """生成基础波形，幅度归一化到 ±1"""
    if wtype == "sine":
        return np.sin(2 * np.pi * t)
    elif wtype == "triangle":
        return 2 * np.abs(2 * (t - np.floor(t + 0.5))) - 1   # -1~1
    elif wtype == "square":
        return np.sign(np.sin(2 * np.pi * t))
    else:
        raise ValueError(f"Unsupported wave type {wtype}")


def gen_case(case):
    """生成单个测试场景 C=A+B ，增益=1"""
    t = np.arange(DEPTH) / FS                    # 时间轴
    # 每路振幅减半，保证相加后峰值 ≤ ±127
    scale = (AMPLITUDE // 2)
    wa = scale * _base_wave(case["A"]["type"], case["A"]["freq"] * t)
    wb = scale * _base_wave(case["B"]["type"], case["B"]["freq"] * t)
    wc = wa + wb                                # C = A + B   (增益 1)
    # 量化 & clip
    wc_q = np.clip(np.round(wc), -128, 127).astype(np.int8)
    return wc_q


def write_coe(data: np.ndarray, filename: Path, radix: int):
    with filename.open("w") as f:
        f.write(f"memory_initialization_radix={radix};\n")
        f.write("memory_initialization_vector=\n")
        for i, v in enumerate(data):
            s = str(int(v) & 0xFF) if radix == 10 else f"{int(v)&0xFF:02X}"
            if i == len(data) - 1:
                f.write(s + ";\n")
            else:
                f.write(s + (",\n" if (i + 1) % 16 == 0 else ", "))


def write_txt(data: np.ndarray, filename: Path):
    with filename.open("w") as f:
        f.write("#Idx\tVal\n")
        for i, v in enumerate(data):
            f.write(f"{i}\t{v}\n")


# 生成全部场景
for case in CASES:
    data = gen_case(case)
    tag = case["tag"]
    write_coe(data, Path(f"{OUT_BASE}_{tag}_radix10.coe"), 10)
    write_coe(data, Path(f"{OUT_BASE}_{tag}_radix16.coe"), 16)
    write_txt(data, Path(f"{OUT_BASE}_{tag}.txt"))

print("✅ 全部波形文件已生成")

import numpy as np
from pathlib import Path

# ========= 用户配置 =========
WAVE_TYPE = "triangle"      # 可选: "sine" | "triangle" | "square"
DEPTH = 1024
AMPLITUDE = 127         # 有符号 8bit 最大振幅 ±127
BASE_NAME = f"waveform_{WAVE_TYPE}"
# ===========================


def generate_waveform(wave_type: str, depth: int, amplitude: int) -> np.ndarray:
    """根据类型生成标准周期波形"""
    x = np.linspace(0, 1, depth, endpoint=False)
    if wave_type == "sine":
        y = np.sin(2 * np.pi * x)
    elif wave_type == "triangle":
        y = 2 * np.abs(2 * (x - np.floor(x + 0.5))) - 1
    elif wave_type == "square":
        y = np.sign(np.sin(2 * np.pi * x))
    else:
        raise ValueError(f"不支持的波形类型: {wave_type}")
    y_scaled = np.clip((y * amplitude).round(), -128, 127).astype(np.int8)
    return y_scaled


def write_coe(data: np.ndarray, output_file: Path, radix: int):
    """将 int8 数据写入 COE 文件（radix=10 或 16），满足 Vivado 语法"""
    with open(output_file, "w") as f:
        f.write(f"memory_initialization_radix={radix};\n")
        f.write("memory_initialization_vector=\n")

        for i, val in enumerate(data):
            # --- 数字字符串 ---
            if radix == 10:
                s = str(int(val) & 0xFF)          # 无符号写出 0-255
            elif radix == 16:
                s = f"{int(val) & 0xFF:02X}"      # 两位十六进制
            else:
                raise ValueError("仅支持 radix 10 和 16")

            # --- 分隔符规则 ---
            if i == len(data) - 1:                # 最后一个样本
                f.write(s + ";\n")                # 用分号结束，不能有逗号
            else:
                sep = ", "                        # 默认逗号+空格
                if (i + 1) % 16 == 0:             # 每 16 个换行排版
                    sep = ",\n"
                f.write(s + sep)

    print(f"✅ COE 文件（radix={radix}）已生成: {output_file.name}")


def write_wave_txt(data: np.ndarray, output_file: Path):
    """输出可读性强的 TXT 波形文件，包含 ASCII 图像"""
    with open(output_file, "w") as f:
        f.write("# Index\tValue\tGraph\n")
        for i, val in enumerate(data):
            graph = " " * (val + 128 >> 1) + "*"
            f.write(f"{i:4d}\t{val:4d}\t{graph}\n")
    print(f"📄 波形文本文件已生成: {output_file.name}")


def main():
    data = generate_waveform(WAVE_TYPE, DEPTH, AMPLITUDE)
    out10 = Path(BASE_NAME + "_radix10.coe")
    out16 = Path(BASE_NAME + "_radix16.coe")
    out_txt = Path(BASE_NAME + ".txt")

    write_coe(data, out10, radix=10)
    write_coe(data, out16, radix=16)
    write_wave_txt(data, out_txt)


if __name__ == "__main__":
    main()

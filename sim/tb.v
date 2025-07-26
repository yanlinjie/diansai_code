`timescale 1ns / 1ps

module top_tb;

  reg clk;               // 50MHz 主时钟
  reg reset_n;           // 复位
  reg [7:0] AD0;         // 模拟ADC数据
  wire AD0_CLK;          // 模拟ADC采样时钟

  // 实例化 DUT（Design Under Test）
  top uut (
    .clk(clk),
    .reset_n(reset_n),
    .AD0(AD0),
    .AD0_CLK(AD0_CLK)
  );

  // 主时钟：50MHz -> 20ns 周期
  always #10 clk = ~clk;

  // 参数定义
  integer i;
  integer sample_count1, sample_count2;
  real pi;
  real amp1, amp2;
  real offset;
  real f_sin1, f_sin2, f_sample;
  real A, B, sum;
  real x, y;

  // 类型选择：0 为正弦波，1 为三角波
  integer wave1_type = 0;  // A 波形类型
  integer wave2_type = 0;  // B 波形类型

  initial begin
    // 初始化
    clk = 0;
    reset_n = 0;
    AD0 = 0;

    // 参数设定
    pi = 3.1415926;
    f_sample = 5120000.0;  // 采样频率
    f_sin1 = 50000.0;      // A: 50kHz
    f_sin2 = 100000.0;     // B: 100kHz

    sample_count1 = f_sample / f_sin1;
    sample_count2 = f_sample / f_sin2;

    amp1 = 63.5;           // 振幅 A
    amp2 = 63.5;           // 振幅 B
    offset = 128.0;        // DC 偏置，映射到无符号范围

    #100;
    reset_n = 1;

    i = 0;
    forever begin
      @(posedge AD0_CLK);

      // 信号 A
      if (wave1_type == 0) begin
        A = amp1 * $sin(2 * pi * (i % sample_count1) / sample_count1);
      end else begin
        x = i % sample_count1;
        A = amp1 * (4.0 * x / sample_count1 - 1.0);
        if (x > sample_count1 / 2)
          A = amp1 * (3.0 - 4.0 * x / sample_count1);
      end

      // 信号 B
      if (wave2_type == 0) begin
        B = amp2 * $sin(2 * pi * (i % sample_count2) / sample_count2);
      end else begin
        y = i % sample_count2;
        B = amp2 * (4.0 * y / sample_count2 - 1.0);
        if (y > sample_count2 / 2)
          B = amp2 * (3.0 - 4.0 * y / sample_count2);
      end

      // 合成信号并转换为 8bit 无符号 ADC 格式
      sum = A + B;
      AD0 = $rtoi(offset + sum);

      i = i + 1;
    end
  end

endmodule

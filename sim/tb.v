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

  // 正弦波参数
  integer i;
  integer sample_count1, sample_count2;
  real pi;
  real amp1, amp2;
  real offset;
  real f_sin1, f_sin2, f_sample;
  real sum; //

  initial begin
    // 初始化
    clk = 0;
    reset_n = 0;
    AD0 = 0;

    // 参数定义
    pi = 3.1415926;
    f_sample = 5120000.0; // 采样频率：35 MHz
    f_sin1 = 50000.0;       // 正弦 A 频率：50kHz
    f_sin2 = 100000.0;      // 正弦 B 频率：100kHz

    sample_count1 = f_sample / f_sin1; // 700
    sample_count2 = f_sample / f_sin2; // 350

    amp1 = 63.5; // 每个波振幅，合起来不超过 ±127
    amp2 = 63.5;
    offset = 128.0; // 0V 对应 128

    // 等待系统稳定
    #100;
    reset_n = 1;

    // 正弦波模拟ADC输入
    i = 0;
    forever begin
      @(posedge AD0_CLK);

      // A + B 信号
      sum = amp1 * $sin(2 * pi * i / sample_count1)
          + amp2 * $sin(2 * pi * i / sample_count2);

      // 中心对称映射到 8位无符号
      AD0 = $rtoi(offset + sum);

      i = i + 1;
    end
  end

endmodule

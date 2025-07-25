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
  integer sample_count;
  real pi;
  real amplitude;
  real offset;
  real f_sin, f_sample;

  initial begin
    // 初始化
    clk = 0;
    reset_n = 0;
    AD0 = 0;

    // 配置参数
    pi = 3.1415926;
    amplitude = 127.0;     // ±127，对应 ±5V
    offset = 128.0;        // 0V → 128
    f_sample = 35000000.0; // 采样频率：35MHz
    f_sin = 50000.0;       // 正弦波频率：50kHz
    sample_count = f_sample / f_sin; // 一个周期采样点数：700

    // 释放复位
    #100;
    reset_n = 1;

    // 正弦波模拟ADC输入
    i = 0;
    forever begin
      @(posedge AD0_CLK);
      AD0 = $rtoi(offset + amplitude * $sin(2 * pi * i / sample_count));
      i = (i + 1) % sample_count;
    end
  end

endmodule

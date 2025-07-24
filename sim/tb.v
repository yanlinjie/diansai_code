`timescale 1ns / 1ps

module top_tb;

  reg clk;               // 50MHz 主时钟
  reg reset_n;           // 复位
  reg [7:0] AD0;         // 模拟ADC数据
  wire AD0_CLK;           // 模拟ADC采样时钟

  // 实例化 DUT（Design Under Test）
  top uut (
    .clk(clk),
    .reset_n(reset_n),
    .AD0(AD0),
    .AD0_CLK(AD0_CLK)
  );

  // 生成主时钟 clk：周期 20ns => 50MHz
  always #10 clk = ~clk;

  // 生成 ADC 采样时钟 AD0_CLK：周期 28.57ns => ~35MHz
  // always #14.28 AD0_CLK = ~AD0_CLK;

  // 正弦波采样参数
  integer i;
  real pi = 3.1415926;
  real amplitude = 127.0; // 振幅范围 ±127，输出加 128 映射到 0~255
  real offset = 128.0;

 initial begin
  // 初始状态
  clk = 0;
  reset_n = 0;
  AD0 = 0;
  #100;
  reset_n = 1;

  // 无限循环正弦波输入
  i = 0;
  forever begin
    @(posedge AD0_CLK);
    AD0 = $rtoi(offset + amplitude * $sin(2 * pi * i / 1024.0));
    i = (i + 1) % 1024;
  end
end
endmodule

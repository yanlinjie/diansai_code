//uesed to diff 波形类型 && 波形频率 && 相位
// output 波形类型 波形频率 波形相位
//处理方法 要么最明显一个峰 ，要么最明显的两个峰
//一个峰的情况 两个三角波同频率 两个正弦波同频率
//两个峰的情况  
/*
    20~100khz
*/
module process_fft_data #(
    parameter triangle_3 = 2770, //参数化 可以根据后续的实际振幅进行调整
    parameter triangle_5 = 954
) 
(
    input                               clk                        ,
    input                               rst                        ,
    input              [  47:0]         m_axis_data_tdata          ,
    input                               m_axis_data_tvalid         ,
    input                               update                     ,

    output                              cordic_down                ,
    output             [   1:0]         wave_type                  ,

    output             [  31:0]         max1_val                   ,
    output             [  31:0]         max2_val                   ,

    output             [   9:0]         max1_idx                   ,
    output             [   9:0]         max2_idx                    

     
);

assign wave_type = wave_style;
wire            signed [  23:0]         re_data                    ;
wire            signed [  23:0]         im_data                    ;
wire                   [  47:0]         fft_abs                    ;
assign re_data = m_axis_data_tdata[23:0];
assign im_data = m_axis_data_tdata[47:24];

//平方
assign fft_abs = $signed(re_data)*$signed(re_data)+$signed(im_data)*$signed(im_data);

wire m_axis_dout_tvalid;
wire [31:0]m_axis_dout_tdata;
//开根 
cordic_0 u_cordic_0(
    .aclk                              (clk                       ),
    .s_axis_cartesian_tvalid           (m_axis_data_tvalid        ),
    .s_axis_cartesian_tdata            (fft_abs                   ),
    .m_axis_dout_tvalid                (m_axis_dout_tvalid        ),
    .m_axis_dout_tdata                 (m_axis_dout_tdata         ) 

);


localparam                              idle = 0                   ;
localparam                              write_to_bram = 1          ;//写入的同时找最明显的两个峰值 
localparam                              one_peak_read = 2          ;//一个峰值的情况
localparam                              one_peak_read_nop = 3      ;
localparam                              one_peak_compare =4        ;

localparam                              two_peak_read = 5          ;//两个峰值的情况
localparam                              two_peak_compare = 6       ;


reg [4:0] state;
/*
    wave_style
    000: nothing
    100: sin + sin
    110: triangle + sin
    101: sin + triangle
    111: triangle + triangle
*/
reg [2:0]wave_style; 
reg [5:0] cnt; //用于计数;

wire  [31:0] ampl_1; 
wire  [1:0]result;

assign result = (ampl_1 + (triangle_3 >> 1)) / triangle_3;//四舍五入
assign ampl_1 = douta;

reg [31:0] two_peak_3x1_ampl;
reg [31:0] two_peak_5x1_ampl;
reg [31:0] two_peak_3x2_ampl;
reg [31:0] two_peak_5x2_ampl;
wire [1:0] result_3x1 ;
wire [1:0] result_3x2 ;
wire [1:0] result_5x1 ;
wire [1:0] result_5x2 ;
assign result_3x1 = (two_peak_3x1_ampl + (triangle_3 >> 1)) / triangle_3;
assign result_3x2 = (two_peak_3x2_ampl + (triangle_3 >> 1)) / triangle_3;
assign result_5x1 = (two_peak_5x1_ampl + (triangle_5 >> 1)) / triangle_5;
assign result_5x2 = (two_peak_5x2_ampl + (triangle_5 >> 1)) / triangle_5;


always @(posedge clk) begin
    if (rst) begin
        state <= idle;
        wea <= 0;
        addra <= 0;
        cnt <= 0;

    end else begin
        case (state)
            idle: begin
                    state <= write_to_bram;
            end
            write_to_bram: begin
                if (m_axis_dout_tvalid) begin
                    wea <= 1; 
                    addra <= num; 
                    dina <= m_axis_dout_tdata; 
                    // state <= two_peak; // 假设两个峰值的情况
                end 
                if (cordic_down) begin //开根号完成 并且存储完成
                        if ( max1_val/max2_val == 1) begin  
                            state <= two_peak_read; // 处理两个峰值的情况
                        end else begin
                            state <= one_peak_read; // 处理一个峰值的情况
                        end
                end
            end
//* note 一个峰的情况 即：同频情况。 
/*
    1. 两个正弦波同频率            一个峰
    2. 两个三角波同频率            一个峰 + 小峰
    3. 一个正弦波和一个三角波同频率 一个峰 + 小峰
    通过 3*max2_idx 中的数据进行判断 目前 三角波的三次谐波 是2770 (这个和实际的振幅有关)
*/
            one_peak_read: begin //read data
                wea <= 0;
                addra <= 3*max1_idx; //next clock output data
                state <= one_peak_read_nop;
                max2_idx <= max1_idx;
                max2_val <= max1_val;
            end
            one_peak_read_nop : begin
                // ampl_1 <= douta;
                state <= one_peak_compare;
            end
            one_peak_compare : begin
                if (result == 1) begin // 说明一个三角波
                    wave_style <= 3'b110;
                end else if (result == 2) begin //two triangle
                     wave_style <= 3'b111;
                end else wave_style <= 3'b100; //two sin
                state <= idle; // 处理完毕
            end
/*
    两个主峰: 说明两个信号频率不相同
    1.sin + sin             
    2.sin + triangle        
    3.triangle + triangle
    两个主峰 + 四个小峰 = six data -2 = 4 ; 3*idx && 5*idx
*/

            two_peak_read: begin
                cnt <= cnt + 1;
                wea <= 0;
                if (cnt == 0) begin
                    addra <= 3*max1_idx; 

                end else if (cnt == 1) begin
                    addra <= 3*max2_idx; 
                    two_peak_3x1_ampl <= douta; // 3*max1_idx 的数据
                end else if (cnt == 2) begin
                    addra <= 5*max1_idx; 
                    two_peak_3x2_ampl <= douta; // 3*max2_idx 的数据
                end else if (cnt == 3) begin
                    addra <= 5*max2_idx; 
                    two_peak_5x1_ampl <= douta; // 5*max1_idx 的数据
                end else if (cnt == 4) begin
                    two_peak_5x2_ampl <= douta; // 5*max2_idx 的数据
                end else if (cnt == 5) begin
                    state <= two_peak_compare; 
                end
//!记得清零cnt                
            end
            two_peak_compare:begin
                cnt <= 0; //清零
                wave_style[2] <= 1'b1; //清零
                if (result_3x1 == 1 || result_3x2 == 1) begin
                    wave_style[0] <= 1'b1; // x + triangle 
                end else begin
                    wave_style[0] <= 1'b0; // x + sin
                end
                if (result_5x1 == 1 || result_5x2 == 1) begin
                    wave_style[1] <= 1'b1; // triangle + x
                end else begin
                    wave_style[1] <= 1'b0; // sin + x
                end
            end
            default: state <= idle;
        endcase
    end
end



wire                                    clka                       ;
wire                                    ena                        ;
reg                    [   0:0]         wea                        ;
reg                    [   9:0]         addra                      ;
reg                    [  31:0]         dina                       ;
wire                   [  31:0]         douta                      ;

assign clka = clk;
assign ena = 1; // always enable

blk_mem_gen_2 u_dist_mem_gen_1024x24(
    .clka                              (clka                   ),
    .ena                               (ena                    ),
    .wea                               (wea                    ),
    .addra                             (addra                  ),
    .dina                              (dina                   ),
    .douta                             (douta                  ) 
);








/***************可以扩展为信号检测 最后需要分辨三角波和正弦波******************/
//分离 针对于两个sin相加 no uesd
//max3 no used
reg [31:0] max1_val, max2_val , max3_val;
reg [9:0] max1_idx, max2_idx , max3_idx; //max1为低点 max2为高点 针对于num
reg [9:0] num;//用于分离



//三角波可以继续加入 新的 找max 以及对应的 val 和 idx 
always @(posedge clk) begin
    if (rst) begin
        max1_val <= 0;
        max1_idx <= 0;

        max2_idx <= 0;
        max2_val <= 0;

    end else begin
        if (m_axis_dout_tvalid  && num < 511 && num != 0 ) begin //防止基波写入 直流分量
            if (m_axis_dout_tdata > max1_val ) begin

                max2_val <= max1_val;
                max2_idx <= max1_idx;

                max1_val <= m_axis_dout_tdata;
                max1_idx <= num;

            end else if (m_axis_dout_tdata > max2_val ) begin
                max2_val <= m_axis_dout_tdata;
                max2_idx <= num;
            end 
        end  else if (max1_idx > max2_idx) begin
                max1_idx <= max2_idx;
                max2_idx <= max1_idx;
            end   
     
        else if ( update) begin //!记得清0
                max1_val <= 0;
                max2_val <= 0;
                max1_idx <= 0;
                max2_idx <= 0;

        end
    end
end


//计数 
reg cordic_down;
always @(posedge clk) begin
    if (rst) begin
        num <= 10'h0; 
        cordic_down <= 0;
    end  else begin        
    if (m_axis_dout_tvalid) begin
        num <= num + 1;
        if (num == 1022) begin
            cordic_down <= 1;
        end
    end else begin
            num <= 10'h0;
            cordic_down <= 0;
        end 
    end
end

//对开根号的数据进行存储，再进行分析 相当于一张频谱图


endmodule
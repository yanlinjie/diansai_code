//uesed to diff 波形类型 && 波形频率 && 相位
// output 波形类型 波形频率 波形相位
module process_fft_data (
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

/***************可以扩展为信号检测 最后需要分辨三角波和正弦波******************/
//分离 针对于两个sin相加 no uesd
reg [31:0] max1_val, max2_val;
reg [9:0] max1_idx, max2_idx; //max1为低点 max2为高点
reg [9:0] num;//用于分离
//三角波可以继续加入 新的 找max 以及对应的 val 和 idx 
always @(posedge clk) begin
    if (rst) begin
        max1_val <= 0;
        max2_val <= 0;

        max1_idx <= 0;
        max2_idx <= 0;
    end else begin
        if (m_axis_dout_tvalid  && num < 511 ) begin
            if (m_axis_dout_tdata > max1_val ) begin
                max2_val <= max1_val;
                max2_idx <= max1_idx;

                max1_val <= m_axis_dout_tdata;
                max1_idx <= num;
            end else if (m_axis_dout_tdata > max2_val ) begin
                max2_val <= m_axis_dout_tdata;
                max2_idx <= num;
            end
            else if (max1_idx > max2_idx) begin
                max1_idx <= max2_idx;
                max2_idx <= max1_idx;
            end   
        end 
     
        else if ( update) begin //!记得清0
                max1_val <= 0;
                max2_val <= 0;
                max1_idx <= 0;
                max2_idx <= 0;
        end
    end
end

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

endmodule
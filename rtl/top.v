//v1.0该版本代码 ram读出信号后做fft 再存入ram中 再进行ifft
//v2.0版本 根据 H题 目前没有配套的adc 和 dac 只从ram中读信号 先分离两个正弦波和（先不判断是否为正弦波还是三角波 
module top (
    input                               clk                        ,//50Mhz
    input              [   7:0]         AD0                        ,
    output                              AD0_CLK                    ,
    input                               reset_n                    ,
    output             [   7:0]         DA0_Data                   ,
    output                              DA0_Clk                    ,
    output             [   7:0]         DA1_Data                   ,
    output                              DA1_Clk                     
);


//debug
ila_0 u_ila_0 (
    .clk                               (clk                       ),
    .probe0                            (s_axis_data_tvalid        ),
    .probe1                            (bram_doutb                ),
    .probe2                            (m_axis_dout_tvalid        ),
    .probe3                            (m_axis_dout_tdata         ),
    .probe4                            (adc_addr                  ),
    .probe5                            (adc_data                  ) 
);




wire rst;
assign rst = ~ reset_n;
wire signed [7:0] spo;
reg [9:0] a;

// reg [3:0] state;
reg                                     s_axis_data_tvalid         ;
wire            signed [   7:0]         re_data_in                 ;
reg                                     s_axis_data_tlast          ;
wire            signed [  23:0]         re_data                    ;
wire            signed [  23:0]         im_data                    ;
wire                   [  47:0]         m_axis_data_tdata          ;
wire                   [  47:0]         fft_abs                    ;
wire                                    m_axis_data_tvalid         ;
wire                   [  15:0]         m_axis_data_tuser          ;

wire                                    locked                     ;

/*pll*/
pll upll(
    .clk_out1                          (AD0_CLK                   ),//35M
    .clk_out2                          (DA0_Clk                   ),
    .clk_out3                          (DA1_Clk                   ),
    .reset                             (rst                       ),
    .locked                            (locked                    ),
    .clk_in1                           (clk                       ) 
);



//adc 状态机
localparam adc_idle = 0;
localparam adc_wait_data = 1;
localparam adc_wait_fft = 2;

reg [10:0] adc_addr;
reg [7:0] adc_data;
reg adc_wen;

reg [10:0] bram_addrb;
wire  [7:0] bram_doutb;

reg [4:0] adc_state;
always @(posedge AD0_CLK) begin
    if (!locked) begin
        adc_addr <= 11'h7ff;
        adc_state <= adc_idle;
        adc_wen<= 0;
        adc_data <= 0;
    end else 
    begin
     case (adc_state)
        adc_idle : begin
            adc_state <= adc_wait_data;//等待一帧数据 1024
        end 
        adc_wait_data : begin
            adc_addr <= adc_addr + 1;
            adc_data <= AD0;
            // adc_data <= adc_data + 1;
            adc_wen  <= 1;
            if (adc_addr==1023) begin
                adc_wen<= 0;
                adc_data <= 0;
                adc_state <= adc_wait_fft;
                adc_addr <= 11'h7ff;
            end
        end
        adc_wait_fft :begin
            if (state == wait_new_adc_data) begin
                adc_state <= adc_idle;//开始新的一帧数据
            end 

        end
        default: begin  
        end
    endcase
        end   
end

/*双端口ram 用于处理跨时钟域问题*/
blk_mem_gen_0 u_blk_mem_gen_0(
    .clka                              (AD0_CLK                   ),
    .ena                               (locked                    ),
    .wea                               (adc_wen                   ),
    .addra                             (adc_addr [9:0]                 ),//[9:0
    .dina                              (adc_data                  ),//[7:0

//read
    .clkb                              (clk                       ),
    .enb                               (locked                    ),
    .addrb                             (bram_addrb                ),//[9:0
    .doutb                             (bram_doutb                ) //[7:0
);

wire signed [7:0] adc_signed;
assign adc_signed =  s_axis_data_tvalid ?  ($signed(bram_doutb) - 8'sd128) : 0 ;

/*fft状态机*/
localparam                              idle = 0                   ;
localparam                              wait_config = 1            ;
localparam                              wait_adc_data = 2          ;
localparam                              send_data = 3              ;
localparam                              fft_data_to_bram = 4       ;
localparam                              wait_cordic_down = 8       ;
localparam  process_data = 9;
localparam                              addr_to_zero = 5           ;
localparam                              bram_data_to_ifft = 6      ;
localparam                              wait_new_adc_data = 7      ;


reg [5:0] state ;
wire s_axis_config_tready;
// reg  s_axis_config_tvalid;
always @(posedge clk ) begin
    if (rst  ) begin
        state <= idle;
        s_axis_data_tlast <= 0;
        s_axis_data_tvalid <=0;
        wen <= 0;  
        wen_1 <= 0;  
        // s_axis_config_tvalid <= 0;
    end else begin
        case (state)
            idle : begin
                    state <= wait_config;
                    addr <= 0;
                    addr_1 <= 0;
                    s_axis_data_tlast <= 0;
                    ifft_s_axis_data_tlast <= 0;
                    ifft_s_axis_data_tvalid <= 0;
                    s_axis_data_tvalid <=0;
                    bram_addrb <= 11'h7ff;
            end 
            wait_config: begin 
                            // s_axis_config_tvalid <= 1;
                            if (s_axis_config_tready) begin
                                state <= wait_adc_data;
                            end
                        end
            wait_adc_data :begin
                            if (adc_state == adc_wait_fft) begin
                                state <= send_data;
                            end
            end             
            send_data: begin //给fft输入data
                            if (s_axis_data_tready) begin
                                s_axis_data_tvalid <=1;
                                bram_addrb <= bram_addrb + 1;//
                                 if (bram_addrb== 1023) begin
                                    state <= fft_data_to_bram;//输入结束后 等待数据输出
                                    s_axis_data_tlast <= 0;
                                    bram_addrb <= 11'h7ff;
                                end 
                            end
            end
            fft_data_to_bram   : begin //write to two bram
                            s_axis_data_tvalid <=0;
                            if (m_axis_data_tvalid) begin
                                addr <= m_axis_data_tuser;
                                data <= m_axis_data_tdata;
                                wen <= 1;  

                                addr_1 <= m_axis_data_tuser;
                                data_1 <= m_axis_data_tdata;
                                wen_1 <= 1;  
                            end
                            if (m_axis_data_tlast) begin //输出last信号后，应该还没完全计算完成吧 开根计算有一个时间差值
                                state <= wait_cordic_down; 
                            end
            end 
            wait_cordic_down : begin
                            addr <= 0;
                            wen <= 0;
                            addr_1 <= 0;
                            wen_1 <= 0;
                            if (cordic_down) begin //开根完成
                                state <= process_data ;
                            end
            end
            process_data : begin //目前只考虑两个正弦波相加
                            addr <= addr + 1;
                            data <= 0;
                            wen <= 1;
                            addr_1 <= addr_1 + 1;
                            data_1 <= 0;
                            wen_1 <= 1;
                            if (addr == (max1_idx - 1)) begin
                                // data <= 0;
                                wen <= 0;
                            end 
                            if (addr_1 == (max2_idx - 1)) begin
                                wen_1 <= 0;
                                // data_1 <= 0;
                            end
                            if (addr == 1023) begin
                                state <= addr_to_zero;
                            end
                             
            end

            addr_to_zero : begin //清零addr
                            addr <= 0;
                            wen <= 0;
                            addr_1 <= 0;
                            wen_1 <= 0;
                            state <= bram_data_to_ifft;
            end
            bram_data_to_ifft : begin //这里用的是bram read data to ifft
                            // wen <= 0;
                            if (ifft_s_axis_data_tready) begin
                                ifft_s_axis_data_tvalid <=1;
                                addr <= addr + 1;
                                addr_1 <= addr_1 + 1;
                                if (addr== 1023) begin
                                    state <= wait_new_adc_data;//输入结束后 等待数据输出
                                    ifft_s_axis_data_tlast <= 0;
                                    addr <= 0;
                                    addr_1 <= 0;
                                end 
                            end       
            end 
            wait_new_adc_data : begin //开始一个新的adc数据
                            ifft_s_axis_data_tvalid <=0;
                            // wen <= 0; 
                            if (adc_state == adc_wait_data) begin
                                state <= wait_adc_data;
                            end
            end 
            default: begin
                
            end
        endcase
    end
end





/*fft ip*/
xfft_0 test (
    .aclk                              (clk                       ),// FFT IP核的时钟输入信号，使用系统时钟clk

  // FFT 配置通道（Configuration channel）
    .s_axis_config_tdata               (8'd1                      ),// 配置数据，通常用于设置FFT参数，例如变换方向、缩放因子等
    .s_axis_config_tvalid              (1'd1                      ),// 配置数据有效信号，表示当前tdata为有效配置
    .s_axis_config_tready              (s_axis_config_tready      ),// 配置就绪信号，FFT IP核准备好接收配置数据时为高

  // FFT 输入数据通道（Input data channel）
    .s_axis_data_tdata                 ({8'd0, adc_signed }       ),// 输入的复数数据，{虚部, 实部}；
    .s_axis_data_tvalid                (s_axis_data_tvalid        ),// 输入数据有效信号，为高表示当前数据有效
    .s_axis_data_tready                (s_axis_data_tready        ),// 输入数据就绪信号，FFT准备好接收数据时为高
    .s_axis_data_tlast                 (s_axis_data_tlast         ),// 输入数据的最后一个样本指示信号，一帧数据结束时为高

  // FFT 输出数据通道（Output data channel）
    .m_axis_data_tdata                 (m_axis_data_tdata         ),// FFT的输出复数数据（{虚部, 实部}）
    .m_axis_data_tuser                 (m_axis_data_tuser         ),
    .m_axis_data_tvalid                (m_axis_data_tvalid        ),// 输出数据有效信号，FFT完成计算后输出数据时为高
    .m_axis_data_tready                (1'd1                      ),// 输出数据就绪信号，始终为1，表示下游模块始终准备好接收数据
    .m_axis_data_tlast                 (m_axis_data_tlast         ) // 输出数据最后一个样本的指示信号

);


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
reg [9:0] max1_idx, max2_idx;
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
        end else if ( state == addr_to_zero) begin //!记得清0
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

/******************two bram to store fft data*********************/
reg                    [   9:0]         addr                       ;
reg                    [  47:0]         data                       ;
reg                                     wen                        ;
wire                   [  47:0]         out_data                   ;
//存入FFT后的数据 48位 
blk_mem_gen_1 u_dist_mem_gen_1024x24(
    .addra                             (addr                      ),//addr [9:0]
    .dina                              (data                      ),//data [47:0]
    .clka                              (clk                       ),
    .ena                               (1'b1                      ),
    .wea                               (wen                       ),//1 w ; 0 r
    .douta                             (out_data                  ) //[47:0]
);


reg                    [   9:0]         addr_1                     ;
reg                    [  47:0]         data_1                     ;
reg                                     wen_1                      ;
wire                   [  47:0]         out_data_1                 ;
//存入FFT后的数据 48位 
blk_mem_gen_1 u_dist_mem_gen_1024x24_1(
    .addra                             (addr_1                    ),//addr [9:0]
    .dina                              (data_1                    ),//data [47:0]
    .clka                              (clk                       ),
    .ena                               (1'b1                      ),
    .wea                               (wen_1                     ),//1 w ; 0 r
    .douta                             (out_data_1                ) //[47:0]
);

/****************************ifft1 start**********************************************************/

wire                                    ifft_s_axis_config_tready  ;
wire                   [  47:0]         ifft_s_axis_data_tdata     ;
reg                                     ifft_s_axis_data_tvalid    ;
wire                                    ifft_s_axis_data_tready    ;
reg                                     ifft_s_axis_data_tlast     ;

assign ifft_s_axis_data_tdata = out_data;


ifft u_ifft1(
    .clk                               (clk                       ),//i
    .rst                               (rst                       ),//i
    .ifft_s_axis_config_tready         (ifft_s_axis_config_tready ),//o
    .ifft_s_axis_data_tdata            (ifft_s_axis_data_tdata    ),
    .ifft_s_axis_data_tvalid           (ifft_s_axis_data_tvalid   ),
    .ifft_s_axis_data_tready           (ifft_s_axis_data_tready   ),//o
    .ifft_s_axis_data_tlast            (ifft_s_axis_data_tlast    ),
    //dac
    .dac_clk                           (DA0_Clk                   ),
    .dac_data                          (dac_data                  ) //o
);

wire signed [7:0] dac_data;
assign DA0_Data = dac_data + 128 ;


/***********************ifft1 end***************************************************************/

//!最后的dac信号需要有一个抬高 相当于要加上128 ，0 和 128 
//两个ifft应该只有数据是可以不一样的，其他的信号感觉可以完全共用
/****************************ifft2 start**********************************************************/

wire                                    ifft_s_axis_config_tready_1  ;
wire                   [  47:0]         ifft_s_axis_data_tdata_1     ;
// reg                                     ifft_s_axis_data_tvalid    ;
wire                                    ifft_s_axis_data_tready_1    ;
// reg                                     ifft_s_axis_data_tlast     ;

assign ifft_s_axis_data_tdata_1 = out_data_1;


ifft u_ifft2(
    .clk                               (clk                       ),//i
    .rst                               (rst                       ),//i
    .ifft_s_axis_config_tready         (ifft_s_axis_config_tready_1 ),//o
    .ifft_s_axis_data_tdata            (ifft_s_axis_data_tdata_1  ),
    .ifft_s_axis_data_tvalid           (ifft_s_axis_data_tvalid   ),
    .ifft_s_axis_data_tready           (ifft_s_axis_data_tready_1   ),//o
    .ifft_s_axis_data_tlast            (ifft_s_axis_data_tlast    ),
    //dac
    .dac_clk                           (DA1_Clk                   ),
    .dac_data                          (dac_data_1                  ) //o
);

wire signed [7:0] dac_data_1;
assign DA1_Data = dac_data_1 + 128 ;

/***********************ifft2 end***************************************************************/

endmodule
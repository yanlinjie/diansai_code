//v1.0该版本代码 ram读出信号后做fft 再存入ram中 再进行ifft
//v2.0版本 根据 H题 目前没有配套的adc 和 dac 只从ram中读信号 先分离两个正弦波和（先不判断是否为正弦波还是三角波 
module top (
    input clk,//50Mhz
    input [7:0]AD0, 
    output AD0_CLK,
    input reset_n,
    output reg [7:0]DA0_Data, 
    output DA0_Clk
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
reg                    [   9:0]         addr                       ;
reg                    [  47:0]         data                       ;
reg                                     wen                        ;
wire                   [  47:0]         out_data                   ;
wire                                    locked                     ;

/*pll*/
pll upll(
    .clk_out1                          (AD0_CLK                   ),//35M
    .clk_out2                          (DA0_Clk                   ),
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
localparam                              fft_data_to_dram = 4       ;
localparam                              addr_to_zero = 5           ;
localparam                              dram_data_to_ifft = 6      ;
localparam                              wait_new_adc_data = 7      ;


reg [4:0] state ;
wire s_axis_config_tready;
// reg  s_axis_config_tvalid;
always @(posedge clk ) begin
    if (rst  ) begin
        state <= idle;
        s_axis_data_tlast <= 0;
        s_axis_data_tvalid <=0;
        wen <= 0;  
        // s_axis_config_tvalid <= 0;
    end else begin
        case (state)
            idle : begin
                    state <= wait_config;
                    addr <= 0;
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
                                    state <= fft_data_to_dram;//输入结束后 等待数据输出
                                    s_axis_data_tlast <= 0;
                                    bram_addrb <= 11'h7ff;
                                end 
                            end
            end
            fft_data_to_dram   : begin

                            s_axis_data_tvalid <=0;
                            if (m_axis_data_tvalid) begin
                                addr <= m_axis_data_tuser;
                                data <= m_axis_data_tdata;
                                wen <= 1;  
                            end
                            if (m_axis_data_tlast) begin
                                state <= addr_to_zero; 
                            end
            end 
            addr_to_zero : begin //清零addr
                            addr <= 0;
                            wen <= 0;
                            state <= dram_data_to_ifft;
            end
            dram_data_to_ifft : begin //这里用的是dram 
                            // wen <= 0;
                            if (ifft_s_axis_data_tready) begin
                                ifft_s_axis_data_tvalid <=1;
                                addr <= addr + 1;
                                if (addr== 1023) begin
                                    state <= wait_new_adc_data;//输入结束后 等待数据输出
                                    ifft_s_axis_data_tlast <= 0;
                                    addr <= 0;
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


//分离 针对于两个sin相加 no uesd
reg [31:0] max1_val, max2_val;
reg [9:0] max1_idx, max2_idx;
reg [9:0] num;//用于分离

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
        end 
    end

end


always @(posedge clk) begin
    if (rst) begin
        num<=10'h0; 
    end  else if (m_axis_dout_tvalid) begin
        num<=num + 1;
    end else num <= 10'h0;
end

/***************************************/

//存入FFT后的数据 48位 
blk_mem_gen_1 u_dist_mem_gen_1024x24(
    .addra                             (addr                      ),//addr [9:0]
    .dina                              (data                      ),//data [47:0]
    .clka                              (clk                       ),
    .ena                               (1'b1                      ), 
    .wea                               (wen                       ),//1 w ; 0 r
    .douta                             (out_data                  ) //[47:0]
);


/****************************ifft1 start**********************************************************/
wire                   [   7:0]         ifft_s_axis_config_tdata   ;
wire                                    ifft_s_axis_config_tvalid  ;
wire                                    ifft_s_axis_config_tready  ;
wire                   [  47:0]         ifft_s_axis_data_tdata     ;
reg                                     ifft_s_axis_data_tvalid    ;
wire                                    ifft_s_axis_data_tready    ;
reg                                     ifft_s_axis_data_tlast     ;
wire                   [  79:0]         ifft_m_axis_data_tdata     ;
wire                   [  15:0]         ifft_m_axis_data_tuser     ;
wire                                    ifft_m_axis_data_tvalid    ;
wire                                    ifft_m_axis_data_tready    ;
wire                                    ifft_m_axis_data_tlast     ;
/***********/
assign ifft_s_axis_data_tdata = out_data;


/*fft ip used to ifft*/
xfft_1 uxfft_1 (
    .aclk                              (clk                       ),// FFT IP核的时钟输入信号，使用系统时钟clk

  // FFT 配置通道（Configuration channel）
    .s_axis_config_tdata               (8'd0                      ),// 配置数据，通常用于设置FFT参数，例如变换方向、缩放因子等
    .s_axis_config_tvalid              (1'd1                      ),// 配置数据有效信号，表示当前tdata为有效配置
    .s_axis_config_tready              (ifft_s_axis_config_tready ),// 配置就绪信号，FFT IP核准备好接收配置数据时为高

  // FFT 输入数据通道（Input data channel）
    .s_axis_data_tdata                 (ifft_s_axis_data_tdata    ),// 输入的复数数据，{虚部, 实部}；此处虚部为0，实部为bpsk_in
    .s_axis_data_tvalid                (ifft_s_axis_data_tvalid   ),// 输入数据有效信号，为高表示当前数据有效
    .s_axis_data_tready                (ifft_s_axis_data_tready   ),// 输入数据就绪信号，FFT准备好接收数据时为高
    .s_axis_data_tlast                 (ifft_s_axis_data_tlast    ),// 输入数据的最后一个样本指示信号，一帧数据结束时为高

  // FFT 输出数据通道（Output data channel）
    .m_axis_data_tdata                 (ifft_m_axis_data_tdata    ),// FFT的输出复数数据（{虚部, 实部}）
    .m_axis_data_tuser                 (ifft_m_axis_data_tuser    ),
    .m_axis_data_tvalid                (ifft_m_axis_data_tvalid   ),// 输出数据有效信号，FFT完成计算后输出数据时为高
    .m_axis_data_tready                (1'd1                      ),// 输出数据就绪信号，始终为1，表示下游模块始终准备好接收数据
    .m_axis_data_tlast                 (ifft_m_axis_data_tlast    ) // 输出数据最后一个样本的指示信号

);
wire signed [39:0] ifft_re_data;
wire  [7:0] ifft_re_data_1024;//得再把这个数据写到ram里,再通过dac进行输出
assign ifft_re_data = ifft_m_axis_data_tdata[39:0];
assign ifft_re_data_1024 = ifft_re_data / 1024;//其实应该在fft之后就对输出的数据除以1024 这样可以减少对FPGA的资源占用 不过这里最后在ifft做处理也无所谓了

/*使用ram进行存储1024x8*/
/*双端口ram 用于处理跨时钟域问题*/
wire ifft_wen;
wire [9:0] ifft_addr;
wire [7:0] ifft_data;
reg read_en;
reg [9:0] ifft_addrb;
wire [7:0] ifft_doutb;

assign ifft_wen = ifft_m_axis_data_tvalid;
assign ifft_addr = ifft_m_axis_data_tuser;
assign ifft_data = ifft_re_data_1024;



blk_mem_gen_0 ifft_to_ram(
    .clka                              (clk                       ),
    .ena                               (1                         ),
    .wea                               (ifft_wen                  ),
    .addra                             (ifft_addr                 ),//[9:0
    .dina                              (ifft_data                 ),//[7:0

//read
    .clkb                              (DA0_Clk                   ),
    .enb                               (read_en                   ),
    .addrb                             (ifft_addrb                ),//[9:0
    .doutb                             (ifft_doutb                ) //[7:0
);

always @(posedge DA0_Clk) begin
    if (rst) begin
        read_en <= 0;
        ifft_addrb <= 0;
        DA0_Data <= 0;
    end else begin
        read_en <= 1;
        ifft_addrb <= ifft_addrb + 1;
        DA0_Data <= ifft_doutb;     
    end
end

/***********************ifft1 end***************************************************************/


endmodule
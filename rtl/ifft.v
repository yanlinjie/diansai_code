//做ifft 应该是可以直接伴随着dac输出值 
//这里再输入 波形类型 && 波形频率 
//输入相位 用于后续调相位？
// 波形类型 && 波形频率 && 相位 先预留好吧

module ifft (
    input                               clk                        ,//sys clk
    input                               rst                        ,//high active
    
    //data
    output                              ifft_s_axis_config_tready  ,
    input              [  47:0]         ifft_s_axis_data_tdata     ,
    input                               ifft_s_axis_data_tvalid    ,
    output                              ifft_s_axis_data_tready    ,
    input                               ifft_s_axis_data_tlast     ,

    //直接输出adc data吧
    input                               dac_clk                    ,
    output reg         [   7:0]         dac_data                    

);
    
wire                   [  79:0]         ifft_m_axis_data_tdata     ;
wire                   [  15:0]         ifft_m_axis_data_tuser     ;
wire                                    ifft_m_axis_data_tvalid    ;
// wire                                    ifft_m_axis_data_tready    ;
wire                                    ifft_m_axis_data_tlast     ;


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


//maybe read and write confi
blk_mem_gen_0 ifft_to_ram(
    .clka                              (clk                       ),
    .ena                               (1                         ),
    .wea                               (ifft_wen                  ),
    .addra                             (ifft_addr                 ),//[9:0
    .dina                              (ifft_data                 ),//[7:0

//read
    .clkb                              (dac_clk                   ),
    .enb                               (read_en                   ),
    .addrb                             (ifft_addrb                ),//[9:0
    .doutb                             (ifft_doutb                ) //[7:0
);

always @(posedge dac_clk) begin
    if (rst) begin
        read_en <= 0;
        ifft_addrb <= 0;
        dac_data <= 0;
    end else begin
        read_en <= 1;
        ifft_addrb <= ifft_addrb + 1;
        dac_data <= ifft_doutb;     
    end
end





endmodule
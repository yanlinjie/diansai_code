//v1.0该版本代码 ram读出信号后做fft 再存入ram中 再进行ifft
//v2.0版本 根据 H题 目前没有配套的adc 和 dac 只从ram中读信号 先分离两个正弦波和（先不判断是否为正弦波还是三角波 
module top (
    input clk,//50Mhz
    input [7:0]AD0, 
    output AD0_CLK,
    input reset_n
    // output [7:0]DA0_Data, 
    // output DA0_Clk
);


//debug
ila_0 u_ila_0 (
    .clk      (clk),
    .probe0   (s_axis_data_tvalid),
    .probe1   (bram_doutb),
    .probe2   (m_axis_dout_tvalid),
    .probe3   (m_axis_dout_tdata),
    .probe4   (adc_addr),
    .probe5   (adc_data)
);




wire rst;
assign rst = ~ reset_n;
wire signed [7:0] spo;
reg [9:0] a;

// reg [3:0] state;
reg s_axis_data_tvalid;
wire signed [7:0] re_data_in;
reg s_axis_data_tlast;
wire signed[23:0] re_data;
wire signed[23:0] im_data;
wire  [47:0] m_axis_data_tdata;
wire [47:0]fft_abs;
wire m_axis_data_tvalid;
wire [15:0] m_axis_data_tuser;
reg [9:0] addr;
reg [47:0] data;
reg wen;
wire  [47:0] out_data;
wire locked;

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

reg [9:0] adc_addr;
reg [7:0] adc_data;
reg adc_wen;

reg [9:0] bram_addrb;
wire  [7:0] bram_doutb;

reg [4:0] adc_state;
always @(posedge AD0_CLK) begin
    if (!locked) begin
        adc_addr <= 0;
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
    .addra                             (adc_addr                  ),//[9:0
    .dina                              (adc_data                  ),//[7:0

//read
    .clkb                              (clk                       ),
    .enb                               (locked                    ),
    .addrb                             (bram_addrb                ),//[9:0
    .doutb                             (bram_doutb                ) //[7:0
);



/*fft状态机*/
localparam                              idle = 0                   ;
localparam                              wait_config = 1            ;
localparam                              wait_adc_data = 2          ;
localparam                              wait_tready = 3            ;
localparam                              send_data = 4              ;
localparam                              fft_last_data = 5          ;
localparam                              wait_new_adc_data = 6      ;

reg [4:0] state ;
wire s_axis_config_tready;
// reg  s_axis_config_tvalid;
always @(posedge clk ) begin
    if (rst  ) begin
        state <= idle;
        s_axis_data_tlast <= 0;
        s_axis_data_tvalid <=0;
        // s_axis_config_tvalid <= 0;
    end else begin
        case (state)
            idle : begin
                    state <= wait_config;
                    s_axis_data_tlast <= 0;
                    s_axis_data_tvalid <=0;
                    bram_addrb <= 0;
            end 
            wait_config: begin 
                            // s_axis_config_tvalid <= 1;
                            if (s_axis_config_tready) begin
                                state <= wait_adc_data;
                            end
                        end
            wait_adc_data :begin
                            if (adc_state == adc_wait_fft) begin
                                state <= wait_tready;
                            end
            end             
            wait_tready: begin
                            if (s_axis_data_tready ) begin
                                state <= send_data;//to fft
                                bram_addrb <= 0;
                                s_axis_data_tlast <= 0;
                            end
                        end
            send_data: begin
                            if (s_axis_data_tready) begin
                                s_axis_data_tvalid <=1;
                                bram_addrb <= bram_addrb + 1;//
                                 if (bram_addrb== 1023) begin
                                    state <= fft_last_data;//输入结束后 等待输出
                                    s_axis_data_tlast <= 0;
                                    bram_addrb <= 0;
                                    // s_axis_data_tvalid <=0;
                                end 
                            end
            end
            fft_last_data: begin
                            s_axis_data_tvalid <=0;//一帧数据传输结束
                            if (m_axis_data_tlast) begin
                                state <= wait_new_adc_data;
                        
                            end
            end
            wait_new_adc_data : begin
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
    .s_axis_config_tvalid              (1'd1      ),// 配置数据有效信号，表示当前tdata为有效配置
    .s_axis_config_tready              (s_axis_config_tready      ),// 配置就绪信号，FFT IP核准备好接收配置数据时为高

  // FFT 输入数据通道（Input data channel）
    .s_axis_data_tdata                 ({8'd0, bram_doutb}        ),// 输入的复数数据，{虚部, 实部}；
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
















// /*状态机*/
// localparam                              idle = 0                   ;
// localparam                              wait_config = 1            ;
// localparam                              wait_tready = 2            ;
// localparam                              send_data = 3              ;
// localparam                              send_data_1 = 4            ;
// localparam                              fft_last_data = 5          ;
// localparam                              ifft_state = 6             ;
// localparam                              ifft_send_data = 7         ;
// localparam                              ifft_send_data_1 = 8       ;
// localparam                              ifft_fft_last_data = 9     ;
// localparam wait_adc_data = 10;

// // localparam wait_config = 1;
// //后期拿到赛题，可以fft后做信号处理，再存进ram中，ram做缓冲 缓冲完再做ifft 输出波形
// always @(posedge clk) begin
//     if (rst) begin
//         state <= idle;
//     end else begin
//         case (state)
//             idle: begin
//                 state <= wait_config;
//                 // state <= wait_adc_data;//等待一帧adc数据
//                 s_axis_data_tlast <= 0;
//                 s_axis_data_tvalid <=0;
//                 a <= 0;
//                 ifft_s_axis_data_tlast <= 0;
//                 ifft_s_axis_data_tvalid <=0;
//             end 
//             // wait_adc_data : begin
                
//             // end
//             wait_config: begin 
//                             if (s_axis_config_tready) begin
//                                 state <= wait_tready;
//                             end
//                         end
//             wait_tready: begin
//                             if (s_axis_data_tready ) begin
//                                 // wen <= 0;//存储fft数据的ram 
//                                 state <= send_data;
//                                 a <= 0;
//                                 s_axis_data_tlast <= 0;
//                                 // re_data_in <= spo ;
//                             end
//                         end
//             send_data: begin
//                             if (s_axis_data_tready) begin
//                                 state <= send_data_1;
//                                 s_axis_data_tvalid <=1;
//                                 a <= 0;//
//                             end
//             end 
//             send_data_1: begin
//                             if (s_axis_data_tready) begin
//                                 state <= send_data_1;
//                                 s_axis_data_tvalid <=1;
//                                 a <= a+1;
//                                 if (a == 1022) begin
//                                     s_axis_data_tlast <= 1;
//                                 end
//                                 else if (a == 1023) begin
//                                     state <= fft_last_data;//输入结束后 等待输出
//                                     s_axis_data_tlast <= 0;
//                                     a <= 0;
//                                     s_axis_data_tvalid <=0;
//                                 end
//                             end
//             end     
//             fft_last_data:begin //向ram中存入数据
//                                 state <= fft_last_data;
//                                 s_axis_data_tlast <= 0;
//                             if(m_axis_data_tvalid)begin
//                                 addr <= m_axis_data_tuser;
//                                 data <= m_axis_data_tdata;
//                                 wen <= 1;
//                             end

//                             if (m_axis_data_tlast) begin
//                                 state <= ifft_state; 
//                             end
//             end  
//             //上面是fft存值 下面是ifft 从ram中读值
//             ifft_state:   begin
//                                 wen <= 0;
//                                 if (ifft_s_axis_data_tready) begin
//                                     addr<=0;
//                                     state <= ifft_send_data;
//                                 end
//             end     
//             //ifft   
//             ifft_send_data:begin
//                                 if (ifft_s_axis_data_tready) begin
//                                     state <= ifft_send_data_1;
//                                     ifft_s_axis_data_tvalid <=1;
//                                     addr <= 0;//
//                                 end
//             end    
//             ifft_send_data_1:begin
//                             if (ifft_s_axis_data_tready) begin
//                                 state <= ifft_send_data_1;
//                                 ifft_s_axis_data_tvalid <=1;
//                                 addr <= addr + 1;
//                                 if (addr == 1022) begin
//                                     ifft_s_axis_data_tlast <= 1;
//                                 end
//                                 else if (addr == 1023) begin
//                                     state <= ifft_fft_last_data;//输入结束后 等待输出
//                                     ifft_s_axis_data_tlast <= 0;
//                                     addr <= 0;
//                                     ifft_s_axis_data_tvalid <=0;
//                                 end
//                             end 
//             end 
//             ifft_fft_last_data:begin
                
//             end
//             default: state <= idle;
//         endcase
//     end
// end

// assign re_data_in = spo;
// assign we = 0;


// dist_mem_gen_0 u_dist_mem_gen_0(
//     .a   	(a    ),//addr
//     .d   	(   ),//data 
//     .clk 	(clk  ),
//     .we  	(we   ),//1 w ; 0 r
//     .spo 	(spo  )
// );



// /*fft ip*/
// xfft_0 test (
//     .aclk                              (clk                       ),// FFT IP核的时钟输入信号，使用系统时钟clk

//   // FFT 配置通道（Configuration channel）
//     .s_axis_config_tdata               (8'd1                      ),// 配置数据，通常用于设置FFT参数，例如变换方向、缩放因子等
//     .s_axis_config_tvalid              (1'd1                      ),// 配置数据有效信号，表示当前tdata为有效配置
//     .s_axis_config_tready              (s_axis_config_tready      ),// 配置就绪信号，FFT IP核准备好接收配置数据时为高

//   // FFT 输入数据通道（Input data channel）
//     .s_axis_data_tdata                 ({8'd0, re_data_in}        ),// 输入的复数数据，{虚部, 实部}；
//     .s_axis_data_tvalid                (s_axis_data_tvalid        ),// 输入数据有效信号，为高表示当前数据有效
//     .s_axis_data_tready                (s_axis_data_tready        ),// 输入数据就绪信号，FFT准备好接收数据时为高
//     .s_axis_data_tlast                 (s_axis_data_tlast         ),// 输入数据的最后一个样本指示信号，一帧数据结束时为高

//   // FFT 输出数据通道（Output data channel）
//     .m_axis_data_tdata                 (m_axis_data_tdata         ),// FFT的输出复数数据（{虚部, 实部}）
//     .m_axis_data_tuser                 (m_axis_data_tuser         ),
//     .m_axis_data_tvalid                (m_axis_data_tvalid        ),// 输出数据有效信号，FFT完成计算后输出数据时为高
//     .m_axis_data_tready                (1'd1                      ),// 输出数据就绪信号，始终为1，表示下游模块始终准备好接收数据
//     .m_axis_data_tlast                 (m_axis_data_tlast         ),// 输出数据最后一个样本的指示信号

//   // 事件指示（Event indicators），用于调试和错误监测
//     .event_frame_started               (event_frame_started       ),// 一帧数据开始处理时置位
//     .event_tlast_unexpected            (event_tlast_unexpected    ),// 收到意外的TLAST（即数据帧结束）信号时置位
//     .event_tlast_missing               (event_tlast_missing       ),// TLAST丢失时置位，表示一帧数据结束标志未收到
//     .event_status_channel_halt         (event_status_channel_halt ),// 配置通道停止（不再传输数据）时置位
//     .event_data_in_channel_halt        (event_data_in_channel_halt),// 输入数据通道停止时置位
//     .event_data_out_channel_halt       (event_data_out_channel_halt) // 输出数据通道停止时置位
// );


// assign re_data = m_axis_data_tdata[23:0];
// assign im_data = m_axis_data_tdata[47:24];

// //平方
// assign fft_abs = $signed(re_data)*$signed(re_data)+$signed(im_data)*$signed(im_data);

// wire m_axis_dout_tvalid;
// wire [31:0]m_axis_dout_tdata;
// //开根
// cordic_0 u_cordic_0(
//     .aclk                              (clk                       ),
//     .s_axis_cartesian_tvalid           (m_axis_data_tvalid        ),
//     .s_axis_cartesian_tdata            (fft_abs                   ),
//     .m_axis_dout_tvalid                (m_axis_dout_tvalid        ),
//     .m_axis_dout_tdata                 (m_axis_dout_tdata         ) 

// );

// //分离 
// reg [31:0] max1_val, max2_val;
// reg [9:0] max1_idx, max2_idx;

// always @(posedge clk) begin
//     if (rst) begin
//         max1_val <= 0;
//         max2_val <= 0;
//         max1_idx <= 0;
//         max2_idx <= 0;
//     end
//     if (m_axis_dout_tvalid  && num < 512 ) begin
//         if (m_axis_dout_tdata > max1_val ) begin
//             max2_val <= max1_val;
//             max2_idx <= max1_idx;
//             max1_val <= m_axis_dout_tdata;
//             max1_idx <= num;
//         end else if (m_axis_dout_tdata > max2_val ) begin
//             max2_val <= m_axis_dout_tdata;
//             max2_idx <= num;
//         end
//     end
// end


// reg [15:0] num;
// always @(posedge clk) begin
//     if (rst) begin
//         num<=16'h0;
//     end  else if (m_axis_dout_tvalid) begin
//         num<=num + 1;
//     end else num <= 16'h0;
// end
// /********************************************/
// // localparam sep_idle = 0;
// // localparam to_ram = 1;
// // reg [1:0] sep_state;

// // always @(posedge clk ) begin
// //     if (rst) begin
// //         sep_state <= sep_idle;
// //     end else if
// // end
// //信号1
// /*计算结果存入到ram中*/
// // ram1024x32 u0ram1024x32(
// //     .a  (   );// input              [   9:0]         a                          ;
// //     .d  (   );// input              [  31:0]         d                          ;
// //     .clk(   );// input                               clk /* synthesis syn_isclock = 1 */;
// //     .we (   );// input                               we                         ;
// //     .spo(   ) // output             [  31:0]         spo                        ;
// // );
// // //信号2
// // ram1024x32 u1ram1024x32(
// //     .a  (   );// input              [   9:0]         a                          ;
// //     .d  (   );// input              [  31:0]         d                          ;
// //     .clk(   );// input                               clk /* synthesis syn_isclock = 1 */;
// //     .we (   );// input                               we                         ;
// //     .spo(   ) // output             [  31:0]         spo                        ;
// // );


// // reg [9:0] addr;
// // reg [47:0] data;
// // reg wen;
// // reg [47:0] out_data;

// //存入FFT后的数据 48位 
// dist_mem_gen_1024x24 u_dist_mem_gen_1024x24(
//     .a                                 (addr                      ),//addr [9:0]
//     .d                                 (data                      ),//data [47:0]
//     .clk                               (clk                       ),
//     .we                                (wen                       ),//1 w ; 0 r
//     .spo                               (out_data                  ) //[47:0]
// );

// /***********/
// wire                   [   7:0]         ifft_s_axis_config_tdata   ;
// wire                                    ifft_s_axis_config_tvalid  ;
// wire                                    ifft_s_axis_config_tready  ;
// wire                   [  47:0]         ifft_s_axis_data_tdata     ;
// reg                                     ifft_s_axis_data_tvalid    ;
// wire                                    ifft_s_axis_data_tready    ;
// reg                                     ifft_s_axis_data_tlast     ;
// wire                   [  79:0]         ifft_m_axis_data_tdata     ;
// wire                   [  15:0]         ifft_m_axis_data_tuser     ;
// wire                                    ifft_m_axis_data_tvalid    ;
// wire                                    ifft_m_axis_data_tready    ;
// wire                                    ifft_m_axis_data_tlast     ;
// /***********/
// assign ifft_s_axis_data_tdata = out_data;


// /*fft ip used to ifft*/
// xfft_1 uxfft_1 (
//     .aclk                              (clk                       ),// FFT IP核的时钟输入信号，使用系统时钟clk

//   // FFT 配置通道（Configuration channel）
//     .s_axis_config_tdata               (8'd0                      ),// 配置数据，通常用于设置FFT参数，例如变换方向、缩放因子等
//     .s_axis_config_tvalid              (1'd1                      ),// 配置数据有效信号，表示当前tdata为有效配置
//     .s_axis_config_tready              (ifft_s_axis_config_tready ),// 配置就绪信号，FFT IP核准备好接收配置数据时为高

//   // FFT 输入数据通道（Input data channel）
//     .s_axis_data_tdata                 (ifft_s_axis_data_tdata        ),// 输入的复数数据，{虚部, 实部}；此处虚部为0，实部为bpsk_in
//     .s_axis_data_tvalid                (ifft_s_axis_data_tvalid   ),// 输入数据有效信号，为高表示当前数据有效
//     .s_axis_data_tready                (ifft_s_axis_data_tready   ),// 输入数据就绪信号，FFT准备好接收数据时为高
//     .s_axis_data_tlast                 (ifft_s_axis_data_tlast    ),// 输入数据的最后一个样本指示信号，一帧数据结束时为高

//   // FFT 输出数据通道（Output data channel）
//     .m_axis_data_tdata                 (ifft_m_axis_data_tdata    ),// FFT的输出复数数据（{虚部, 实部}）
//     .m_axis_data_tuser                 (ifft_m_axis_data_tuser    ),
//     .m_axis_data_tvalid                (ifft_m_axis_data_tvalid   ),// 输出数据有效信号，FFT完成计算后输出数据时为高
//     .m_axis_data_tready                (1'd1                      ),// 输出数据就绪信号，始终为1，表示下游模块始终准备好接收数据
//     .m_axis_data_tlast                 (ifft_m_axis_data_tlast    )// 输出数据最后一个样本的指示信号

//   // 事件指示（Event indicators），用于调试和错误监测
//     // .event_frame_started               (event_frame_started       ),// 一帧数据开始处理时置位
//     // .event_tlast_unexpected            (event_tlast_unexpected    ),// 收到意外的TLAST（即数据帧结束）信号时置位
//     // .event_tlast_missing               (event_tlast_missing       ),// TLAST丢失时置位，表示一帧数据结束标志未收到
//     // .event_status_channel_halt         (event_status_channel_halt ),// 配置通道停止（不再传输数据）时置位
//     // .event_data_in_channel_halt        (event_data_in_channel_halt),// 输入数据通道停止时置位
//     // .event_data_out_channel_halt       (event_data_out_channel_halt) // 输出数据通道停止时置位
// );
// wire [39:0] ifft_re_data;
// assign ifft_re_data = ifft_m_axis_data_tdata[39:0];
endmodule
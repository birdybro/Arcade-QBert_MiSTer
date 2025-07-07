module ma216_board(
  input clk,
  input clk_sys,
  input reset,

  input [5:0] IP2720,

  output [7:0] audio,

  input rom_init,
  input [17:0] rom_init_address,
  input [7:0] rom_init_data
);

// Mix Votrax audio with existing audio
wire [7:0] votrax_audio;
assign audio = (U7_8 >> 1) + (votrax_audio >> 1); // Simple audio mixing

wire [15:0] AB;
wire [7:0] DBo;
wire WE, irq, U14_AR;
wire [7:0] U4_O, U5_dout, U6_dout;
wire [7:0] U15_D_O;
reg [7:0] SB1, U11_18, U7_8;

reg [7:0] DBi;

always @(posedge clk)
  DBi <= ~U4_O[0] ? U15_D_O : U5_dout | U6_dout;

cpu6502 U3(
  .clk(clk),
  .reset(reset),
  .AB(AB),
  .DI(DBi),
  .DO(DBo),
  .WE(WE),
  .IRQ(~irq),
  .NMI(~U14_AR),
  .RDY(1'b1)
);

x74138 U4(
  .G1(1'b1),
  .G2A(1'b0),
  .G2B(1'b0),
  .A(AB[14:12]),
  .O(U4_O)
);

dpram #(.addr_width(11),.data_width(8)) U5 (
  .clk(clk_sys),
  .addr(AB[10:0]),
  .dout(U5_dout),
  .ce(U4_O[7]),
  .oe(AB[11]),
  .we(rom_init & rom_init_address < 18'h1C800),
  .waddr(rom_init_address),
  .wdata(rom_init_data)
);

dpram #(.addr_width(11),.data_width(8)) U6 (
  .clk(clk_sys),
  .addr(AB[10:0]),
  .dout(U6_dout),
  .ce(U4_O[7]),
  .oe(~AB[11]),
  .we(rom_init & rom_init_address < 18'h1D000),
  .waddr(rom_init_address),
  .wdata(rom_init_data)
);

// U7 U8
always @(posedge clk)
  if (~U4_O[1]) U7_8 <= DBo;

// U11 U18
always @(posedge clk)
  if (~U4_O[3]) U11_18 <= DBo;

// ===================================================================
// Votrax Clock Generation
// ===================================================================
// Generate 720KHz clock from main clock (assuming main clk is much higher)
// Adjust DIVISOR based on your main clock frequency
// For 50MHz: 50,000,000 / 720,000 = ~69.4, use 70
// For 48MHz: 48,000,000 / 720,000 = ~66.7, use 67
parameter VOTRAX_CLK_DIV = 70; // Adjust based on your main clock frequency

reg [$clog2(VOTRAX_CLK_DIV)-1:0] votrax_clk_div;
reg votrax_clk;

always @(posedge clk or posedge reset) begin
  if (reset) begin
    votrax_clk_div <= 0;
    votrax_clk <= 0;
  end else begin
    if (votrax_clk_div == VOTRAX_CLK_DIV-1) begin
      votrax_clk_div <= 0;
      votrax_clk <= ~votrax_clk;
    end else begin
      votrax_clk_div <= votrax_clk_div + 1;
    end
  end
end

// ===================================================================
// Votrax Interface Logic
// ===================================================================
reg [5:0] votrax_phone_latch;
reg votrax_strobe_prev, votrax_strobe;
wire votrax_strobe_edge;

// Latch phone data when CPU writes to Votrax
always @(posedge clk or posedge reset) begin
  if (reset) begin
    votrax_phone_latch <= 6'h3F; // Default to silence
    votrax_strobe_prev <= 0;
  end else begin
    votrax_strobe_prev <= votrax_strobe;
    if (~U4_O[2] && WE) begin // CPU write to Votrax address
      votrax_phone_latch <= ~DBo[5:0]; // Invert as per original interface
    end
  end
end

// Generate strobe edge detection
assign votrax_strobe_edge = votrax_strobe && !votrax_strobe_prev;

// Strobe generation - pulse when CPU writes to Votrax
always @(posedge clk or posedge reset) begin
  if (reset) begin
    votrax_strobe <= 0;
  end else begin
    if (~U4_O[2] && WE) begin
      votrax_strobe <= 1;
    end else if (votrax_strobe_edge) begin
      votrax_strobe <= 0;
    end
  end
end

// ===================================================================
// Votrax SC01A Instance
// ===================================================================
wire votrax_noise_out;
wire [7:0] votrax_debug_sram_0, votrax_debug_sram_1, votrax_debug_sram_2;

votrax_sc01a U14_votrax(
  .clk(votrax_clk),              // 720KHz clock
  .reset_n(~reset),              // Active-low reset
  .p_input(votrax_phone_latch),  // Phone input data
  .pad_stb(votrax_strobe),       // Strobe input
  .noise_out(votrax_noise_out),  // Raw noise output
  .debug_sram_0(votrax_debug_sram_0),
  .debug_sram_1(votrax_debug_sram_1),
  .debug_sram_2(votrax_debug_sram_2)
);

// ===================================================================
// Audio Processing and Output
// ===================================================================
// Convert 1-bit noise to 8-bit audio with simple filtering
reg [7:0] votrax_filter_reg;
reg [7:0] votrax_audio_raw;

always @(posedge votrax_clk or posedge reset) begin
  if (reset) begin
    votrax_filter_reg <= 8'b0;
    votrax_audio_raw <= 8'b0;
  end else begin
    // Simple low-pass filter using shift register
    votrax_filter_reg <= {votrax_filter_reg[6:0], votrax_noise_out};
    
    // Convert to audio level (count 1s in filter register)
    votrax_audio_raw <= (votrax_filter_reg[0] + votrax_filter_reg[1] + 
                        votrax_filter_reg[2] + votrax_filter_reg[3] +
                        votrax_filter_reg[4] + votrax_filter_reg[5] + 
                        votrax_filter_reg[6] + votrax_filter_reg[7]) << 4;
  end
end

// Cross clock domain for audio output
reg [7:0] votrax_audio_sync1, votrax_audio_sync2;
always @(posedge clk or posedge reset) begin
  if (reset) begin
    votrax_audio_sync1 <= 8'b0;
    votrax_audio_sync2 <= 8'b0;
  end else begin
    votrax_audio_sync1 <= votrax_audio_raw;
    votrax_audio_sync2 <= votrax_audio_sync1;
  end
end

assign votrax_audio = votrax_audio_sync2;

// ===================================================================
// AR (Audio Request) Signal Generation
// ===================================================================
// The AR signal indicates when Votrax is ready for new data
// This is a simplified version - you may need to adjust timing
reg ar_counter;
reg U14_AR_internal;

always @(posedge votrax_clk or posedge reset) begin
  if (reset) begin
    ar_counter <= 0;
    U14_AR_internal <= 1; // Ready initially
  end else begin
    if (votrax_strobe_edge) begin
      U14_AR_internal <= 0; // Busy when new phone starts
      ar_counter <= 0;
    end else begin
      // Simple timing - assert AR after some delay
      // This should be based on actual Votrax timing
      if (ar_counter == 1) begin
        U14_AR_internal <= 1;
      end else begin
        ar_counter <= ar_counter + 1;
      end
    end
  end
end

// Synchronize AR signal to main clock domain
reg U14_AR_sync1, U14_AR_sync2;
always @(posedge clk or posedge reset) begin
  if (reset) begin
    U14_AR_sync1 <= 1;
    U14_AR_sync2 <= 1;
  end else begin
    U14_AR_sync1 <= U14_AR_internal;
    U14_AR_sync2 <= U14_AR_sync1;
  end
end

assign U14_AR = U14_AR_sync2;

riot U15(
  .PHI2(clk),
  .RES_N(~reset),
  .CS1(~U4_O[0]),
  .CS2_N(U4_O[0]),
  .RS_N(AB[9]),
  .R_W(~WE),
  .A(AB[6:0]),
  .D_I(DBo),
  .D_O(U15_D_O),
  .PA_I({ &IP2720[3:0], 1'b0, ~IP2720 }),
  .PA_O(),
  .DDRA_O(),
  .PB_I({ ~U14_AR, 1'b1, ~SB1[5:0] }),
  .PB_O(),
  .DDRB_O(),
  .IRQ_N(irq)
);

endmodule
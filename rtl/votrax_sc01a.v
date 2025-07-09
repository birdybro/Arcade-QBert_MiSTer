// ===================================================================
// Votrax SC01A Speech Synthesizer - Verilog Implementation
// Converted from galibert's vsim C++ simulation
// ===================================================================

// Top-level module
module votrax_sc01a (
    input wire clk,           // Master clock
    input wire reset_n,       // Active-low reset
    input wire [5:0] p_input, // Phone input data
    input wire pad_stb,       // Strobe input
    output wire noise_out,    // Noise output
    output wire [7:0] debug_sram_0, // Debug outputs
    output wire [7:0] debug_sram_1,
    output wire [7:0] debug_sram_2
);

    // State registers matching cstate structure
    reg first;
    reg [63:0] ctime;
    reg clk_0, clk_1;
    reg [5:0] gtsr;
    reg gtsr_input;
    reg gtsr_enable_input;
    reg pulse_80Hz;
    reg param_timing_sr_enable;
    reg final_filter_clock;
    reg [16:0] paramsr;
    reg rom_extra, rom_hsel_f1, rom_hsel_f2, rom_hsel_f2q;
    reg rom_hsel_f3, rom_hsel_fa, rom_hsel_fc, rom_hsel_va;
    reg phi1, phi2;
    reg [2:0] stbsr;
    reg input_phone_latch_stb, input_phone_latch_rom;
    reg [5:0] p_stb, p_rom;
    wire [3:0] rom_param, rom_clvd;
    wire [6:0] rom_duration;
    wire rom_cl;
    wire rom_muxed_fx_out;
    reg sram_w, sram_enable_w, sram_enable_hold, sram_r, sram_alt_r;
    reg latch_sram_r, latch_sram_alt_r;
    reg carry1_in, carry1_out, carry2_in, carry2_out;
    reg [7:0] sram [0:6];
    reg [4:0] driver_in;
    reg [11:0] right1;
    reg [1:0] right2;
    reg [3:0] right3;
    reg tick_625hz, tick_208hz, tick_ph;
    reg phone_end, clvd_detect;
    reg [17:0] phc;
    reg [11:0] phc2;
    reg cv_reached, cl_reached, cl_value;
    wire pause;
    reg silent, clc_reset;
    reg [29:0] noise;
    
    // Clock generation - creating clk_0 and clk_1 from master clock
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            clk_0 <= 1'b1;
            clk_1 <= 1'b1;
            ctime <= 64'b0;
        end else begin
            clk_0 <= ~clk_0;
            if (clk_0) begin
                clk_1 <= ~clk_1;
                ctime <= ctime + 1;
            end
        end
    end
    
    // Output assignments
    assign noise_out = noise[29] ^ noise[27];
    assign debug_sram_0 = sram[0];
    assign debug_sram_1 = sram[1];
    assign debug_sram_2 = sram[2];

    // Main timing generation (main_timings function)
    always @(*) begin
        gtsr_enable_input = !(gtsr[1] || gtsr[3] || !gtsr[5]);
        gtsr_input = (gtsr[3] ^ gtsr[5]) || (gtsr[1] && gtsr[3]);
        
        // Hack to get the full cycle and not miss '111'
        if (gtsr[1] && gtsr[3] && !gtsr[5])
            gtsr_input = 1'b0;
    end
    
    always @(negedge clk_1 or negedge reset_n) begin
        if (!reset_n) begin
            gtsr[1] <= 1'b0;
            gtsr[3] <= 1'b0;
            gtsr[5] <= 1'b0;
            pulse_80Hz <= 1'b0;
        end else begin
            gtsr[1] <= !gtsr[0];
            gtsr[3] <= !gtsr[2];
            gtsr[5] <= !gtsr[4];
            pulse_80Hz <= param_timing_sr_enable;
        end
    end
    
    always @(negedge clk_0 or negedge reset_n) begin
        if (!reset_n) begin
            gtsr[0] <= 1'b0;
            gtsr[2] <= 1'b0;
            gtsr[4] <= 1'b0;
            param_timing_sr_enable <= 1'b0;
        end else begin
            if (!gtsr_enable_input && pulse_80Hz)
                gtsr[0] <= gtsr_input;
            gtsr[2] <= !gtsr[1];
            gtsr[4] <= !gtsr[3];
            param_timing_sr_enable <= !gtsr_enable_input;
        end
    end

    // Parameter timing generation (param_timings function)
    integer i;
    always @(negedge clk_1 or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 1; i < 17; i = i + 2) begin
                paramsr[i] <= 1'b0;
            end
        end else if (!param_timing_sr_enable) begin
            for (i = 1; i < 17; i = i + 2) begin
                paramsr[i] <= !paramsr[i-1];
            end
        end
    end
    
    always @(negedge clk_0 or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 2; i < 17; i = i + 2) begin
                paramsr[i] <= 1'b0;
            end
            paramsr[0] <= 1'b0;
        end else begin
            for (i = 2; i < 17; i = i + 2) begin
                paramsr[i] <= !paramsr[i-1];
            end
            paramsr[0] <= !(rom_hsel_f2 && rom_hsel_f2q && rom_hsel_f3 && 
                           rom_extra && rom_hsel_fc && rom_hsel_fa && rom_hsel_va);
        end
    end
    
    // ROM select signals generation
    always @(*) begin
        rom_hsel_f2  = !paramsr[1]  || paramsr[2];
        rom_hsel_f2q = !paramsr[3]  || paramsr[4];
        rom_hsel_f3  = !paramsr[5]  || paramsr[6];
        rom_extra    = !paramsr[7]  || paramsr[8];
        rom_hsel_fc  = !paramsr[9]  || paramsr[10];
        rom_hsel_fa  = !paramsr[11] || paramsr[12];
        rom_hsel_va  = !paramsr[13] || paramsr[14];
        rom_hsel_f1  = !paramsr[15] || paramsr[16];
    end
    
    // Phi clock generation
    reg t_phi1, t_phi2;
    always @(*) begin
        t_phi1 = phi1 || paramsr[5] || paramsr[13];
        phi1 = t_phi1 && rom_hsel_f2 && rom_hsel_fc;
        
        t_phi2 = phi2 || paramsr[1] || paramsr[9];
        phi2 = t_phi2 && rom_hsel_f3 && rom_hsel_va;
    end

    // Phone input handling (phone_input function)
    always @(negedge rom_extra or negedge reset_n) begin
        if (!reset_n) begin
            stbsr[1] <= 1'b0;
        end else begin
            stbsr[1] <= !stbsr[0];
        end
    end
    
    always @(negedge phi1 or negedge reset_n) begin
        if (!reset_n) begin
            stbsr[2] <= 1'b0;
            stbsr[0] <= 1'b0;
        end else begin
            stbsr[2] <= !stbsr[1];
            stbsr[0] <= !input_phone_latch_stb;
        end
    end
    
    reg t_phone_latch;
    always @(*) begin
        t_phone_latch = !input_phone_latch_stb || !stbsr[2];
        input_phone_latch_stb = !t_phone_latch || !pad_stb;
        input_phone_latch_rom = !(stbsr[1] && stbsr[2] && !rom_extra);
    end
    
    always @(negedge input_phone_latch_stb or negedge reset_n) begin
        if (!reset_n) begin
            p_stb <= 6'b0;
        end else begin
            p_stb <= p_input;
        end
    end
    
    always @(negedge input_phone_latch_rom or negedge reset_n) begin
        if (!reset_n) begin
            p_rom <= 6'b0;
        end else begin
            p_rom <= p_stb;
        end
    end

    // Right timing counters (right_timings function)
    always @(negedge rom_hsel_f1 or negedge reset_n) begin
        if (!reset_n) begin
            right1[1] <= 1'b0;
            right2[0] <= 1'b0;
            right3[2] <= 1'b0;
            right3[0] <= 1'b0;
        end else begin
            right1[1] <= right1[0];
            right2[0] <= !right2[1];
            right3[2] <= !right3[3];
            right3[0] <= !right3[1];
        end
    end
    
    always @(negedge rom_hsel_va or negedge reset_n) begin
        if (!reset_n) begin
            right1[0] <= 1'b0;
            right2[1] <= 1'b0;
            right3[3] <= 1'b0;
            right3[1] <= 1'b0;
        end else begin
            right1[0] <= !right1[1];
            right2[1] <= !(!right1[8] || right1[11] || right1[7]);
            right3[3] <= !right1[7];
            right3[1] <= !right3[2];
        end
    end
    
    // Simplified right timing logic (the C++ version has complex loops)
    // This is a more structured approach for hardware
    always @(*) begin
        tick_625hz = right3[0] || !right3[2];
        tick_208hz = right2[0];
    end

    // Phone counter logic (phone_counter function)
    reg phonetime_counter_reset;
    always @(*) begin
        phonetime_counter_reset = input_phone_latch_rom && (phi2 || phc2[0]);
    end
    
    always @(negedge phonetime_counter_reset or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < 18; i = i + 2) begin
                phc[i] <= 1'b0;
            end
        end else begin
            for (i = 0; i < 18; i = i + 2) begin
                phc[i] <= 1'b1;
            end
        end
    end
    
    always @(negedge phi1 or negedge reset_n) begin
        if (!reset_n) begin
            phc[0] <= 1'b0;
        end else begin
            phc[0] <= phc[1];
        end
    end
    
    always @(negedge phi2 or negedge reset_n) begin
        if (!reset_n) begin
            phc[1] <= 1'b0;
        end else begin
            phc[1] <= !phc[0];
        end
    end
    
    // Phone counter comparison
    reg [6:0] phc_compare;
    always @(*) begin
        phc_compare = {phc[17], phc[15], phc[13], phc[11], phc[9], phc[7], phc[5]};
        tick_ph = !phone_end || (phc_compare != rom_duration);
    end

    // Phone counter 2 (phone_counter2 function)
    always @(negedge input_phone_latch_rom or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < 12; i = i + 2) begin
                phc2[i] <= 1'b0;
            end
        end else begin
            for (i = 0; i < 12; i = i + 2) begin
                phc2[i] <= 1'b1;
            end
        end
    end
    
    always @(negedge phi1 or negedge reset_n) begin
        if (!reset_n) begin
            phc2[0] <= 1'b0;
        end else begin
            phc2[0] <= tick_ph;
        end
    end
    
    always @(negedge phi2 or negedge reset_n) begin
        if (!reset_n) begin
            phc2[1] <= 1'b0;
        end else begin
            phc2[1] <= !phc2[0];
        end
    end
    
    always @(*) begin
        phone_end = !phc2[11];
        
        // CLVD detection
        clvd_detect = 1'b0;
        for (i = 0; i < 4; i = i + 1) begin
            if (phc2[3 + 2*i] != rom_clvd[i])
                clvd_detect = 1'b1;
        end
    end

    // Closure/Voicing detection (clv_detect function)
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cv_reached <= 1'b0;
            cl_reached <= 1'b0;
        end else begin
            // Set on phone latch
            if (!input_phone_latch_rom) begin
                cv_reached <= 1'b1;
                cl_reached <= 1'b1;
            end
            // Clear conditionally on clvd_detect or pulse_80Hz
            else if (clvd_detect || pulse_80Hz) begin
                if (!rom_hsel_f1)
                    cv_reached <= 1'b0;
                if (!rom_hsel_fa)
                    cl_reached <= 1'b0;
            end
        end
    end
    
    always @(negedge cl_reached or negedge reset_n) begin
        if (!reset_n) begin
            cl_value <= 1'b0;
        end else begin
            cl_value <= rom_cl;
        end
    end
    
    always @(*) begin
        clc_reset = rom_extra || !(cl_value || silent);
        
        sram_enable_w = (((cl_reached || rom_hsel_fc) && (cv_reached || rom_hsel_fa)) || tick_625hz) && 
                       (!rom_hsel_fc || !rom_hsel_fa || !(pause || silent) || tick_208hz);
    end

    // SRAM update logic (sram_update function)
    reg driver_latch;
    reg sram_io_clear;
    reg [2:0] slot, alt_slot;
    reg [2:0] line;
    reg [2:0] gtsr_state;
    
    always @(*) begin
        driver_latch = !(gtsr[3] && gtsr[5] && clk_1);
        sram_io_clear = !(param_timing_sr_enable || clk_1);
        gtsr_state = {gtsr[1], gtsr[3], gtsr[5]};
        
        // Slot calculation based on GTSR state
        case (gtsr_state)
            3'b110: begin slot = 3'd0; alt_slot = 3'd5; end
            3'b100: begin slot = 3'd1; alt_slot = 3'd6; end
            3'b000: begin slot = 3'd2; alt_slot = 3'd7; end
            3'b001: begin slot = 3'd3; alt_slot = 3'd0; end
            3'b010: begin slot = 3'd4; alt_slot = 3'd1; end
            3'b101: begin slot = 3'd5; alt_slot = 3'd2; end
            3'b011: begin slot = 3'd6; alt_slot = 3'd3; end
            3'b111: begin slot = 3'd7; alt_slot = 3'd4; end
        endcase
        
        slot = (slot + 3'd5) & 3'd7;
        alt_slot = (alt_slot + 3'd5) & 3'd7;
        
        // Line selection based on ROM enables
        line = 3'b111; // Default invalid
        if (!rom_hsel_f1)  line = 3'd0;
        if (!rom_hsel_va)  line = 3'd1;
        if (!rom_hsel_f2)  line = 3'd2;
        if (!rom_hsel_fc)  line = 3'd3;
        if (!rom_hsel_f2q) line = 3'd4;
        if (!rom_hsel_f3)  line = 3'd5;
        if (!rom_hsel_fa)  line = 3'd6;
    end
    
    // SRAM array updates
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < 7; i = i + 1) begin
                sram[i] <= 8'b0;
            end
            sram_enable_hold <= 1'b0;
        end else begin
            // Clear SRAM when sram_io_clear and valid line
            if (sram_io_clear && line != 3'b111) begin
                sram[line] <= 8'h00;
            end
            
            // Update sram_enable_hold
            if (!pulse_80Hz) begin
                sram_enable_hold <= !sram_enable_w;
            end
            
            // SRAM write/clear operations
            if (line != 3'b111 && clk_1 && pulse_80Hz && sram_enable_hold) begin
                if (sram_w) begin
                    sram[line] <= sram[line] | (1 << slot);
                end else begin
                    sram[line] <= sram[line] & ~(1 << slot);
                end
            end
        end
    end
    
    // SRAM read operations
    always @(*) begin
        if (line == 3'b111) begin
            sram_r = 1'b1;
            sram_alt_r = 1'b1;
        end else begin
            sram_r = !(sram[line] & (1 << slot));
            sram_alt_r = (alt_slot < 5) ? !(sram[line] & (1 << alt_slot)) : 1'b1;
        end
    end
    
    // Driver input
    always @(negedge driver_latch or negedge reset_n) begin
        if (!reset_n) begin
            driver_in <= 5'b0;
        end else begin
            if (line == 3'b111) begin
                driver_in <= 5'h1f;
            end else begin
                driver_in <= (~sram[line]) & 5'h1f;
            end
        end
    end

    // Interpolator logic (interpolator function)
    always @(negedge clk_1 or negedge reset_n) begin
        if (!reset_n) begin
            latch_sram_r <= 1'b0;
            latch_sram_alt_r <= 1'b0;
            carry1_out <= 1'b0;
            carry2_out <= 1'b0;
        end else begin
            latch_sram_r <= sram_r;
            latch_sram_alt_r <= sram_alt_r;
            carry1_out <= carry1_in;
            carry2_out <= carry2_in;
        end
    end
    
    reg p263, p217, p182;
    always @(*) begin
        p263 = !latch_sram_r ^ latch_sram_alt_r;
        p217 = !p263 ^ carry1_out;
        p182 = !p217 ^ rom_muxed_fx_out;
        sram_w = p182 ^ carry2_out;
    end
    
    always @(negedge clk_0 or negedge reset_n) begin
        if (!reset_n) begin
            carry1_in <= 1'b0;
            carry2_in <= 1'b0;
        end else begin
            carry1_in <= pulse_80Hz && ((p263 || carry1_out) && (latch_sram_r || latch_sram_alt_r));
            carry2_in <= (!pulse_80Hz) || ((p182 || carry2_out) && (p217 || rom_muxed_fx_out));
        end
    end

    // Noise generator (noise function)
    always @(negedge phi2 or negedge reset_n) begin
        if (!reset_n) begin
            noise[0] <= 1'b0;
            for (i = 2; i < 30; i = i + 2) begin
                noise[i] <= 1'b0;
            end
        end else begin
            // Simplified noise input - in real hardware this would be more complex
            noise[0] <= !(noise[29] ^ noise[27]); // Feedback from output
            for (i = 2; i < 30; i = i + 2) begin
                noise[i] <= !noise[i-1];
            end
        end
    end
    
    always @(negedge phi1 or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 1; i < 30; i = i + 2) begin
                noise[i] <= 1'b0;
            end
        end else begin
            for (i = 1; i < 30; i = i + 2) begin
                noise[i] <= !noise[i-1];
            end
        end
    end

    // ROM instantiation would go here
    votrax_rom u_rom (
        .clk(clk),
        .reset_n(reset_n),
        .p_rom(p_rom),
        .rom_hsel_f1(rom_hsel_f1),
        .rom_hsel_va(rom_hsel_va),
        .rom_hsel_f2(rom_hsel_f2),
        .rom_hsel_fc(rom_hsel_fc),
        .rom_hsel_f2q(rom_hsel_f2q),
        .rom_hsel_f3(rom_hsel_f3),
        .rom_hsel_fa(rom_hsel_fa),
        .gtsr(gtsr),
        .rom_param(rom_param),
        .rom_clvd(rom_clvd),
        .rom_cl(rom_cl),
        .rom_duration(rom_duration),
        .pause(pause),
        .rom_muxed_fx_out(rom_muxed_fx_out)
    );

endmodule

// ===================================================================
// ROM Module Implementation
// ===================================================================
module votrax_rom (
    input wire clk,
    input wire reset_n,
    input wire [5:0] p_rom,
    input wire rom_hsel_f1, rom_hsel_va, rom_hsel_f2, rom_hsel_fc,
    input wire rom_hsel_f2q, rom_hsel_f3, rom_hsel_fa,
    input wire [5:0] gtsr,
    output reg [3:0] rom_param,
    output reg [3:0] rom_clvd,
    output reg rom_cl,
    output reg [6:0] rom_duration,
    output reg pause,
    output reg rom_muxed_fx_out
);

    // ROM data - converted from C++ array
    reg [11:0] rom_data0 [0:63];
    reg [31:0] rom_data1 [0:63];
    
    initial begin
        // Initialize ROM with data from C++ array
        rom_data0[0] = 12'h361; rom_data1[0] = 32'h74688127;
        rom_data0[1] = 12'h161; rom_data1[1] = 32'hd4688127;
        rom_data0[2] = 12'h9a1; rom_data1[2] = 32'hc4688127;
        rom_data0[3] = 12'h0e0; rom_data1[3] = 32'hf0a050a4;
        rom_data0[4] = 12'h0fb; rom_data1[4] = 32'h610316e8;
        rom_data0[5] = 12'h161; rom_data1[5] = 32'h64c9c1a6;
        rom_data0[6] = 12'h7a1; rom_data1[6] = 32'h34c9c1a6;
        rom_data0[7] = 12'h463; rom_data1[7] = 32'hf3cb546c;
        rom_data0[8] = 12'h161; rom_data1[8] = 32'hc4e940a3;
        rom_data0[9] = 12'hb61; rom_data1[9] = 32'h806191a6;
        rom_data0[10] = 12'ha61; rom_data1[10] = 32'h906191a6;
        rom_data0[11] = 12'h9a1; rom_data1[11] = 32'h906191a6;
        rom_data0[12] = 12'h7a3; rom_data1[12] = 32'h66a58832;
        rom_data0[13] = 12'ha61; rom_data1[13] = 32'he6241936;
        rom_data0[14] = 12'h173; rom_data1[14] = 32'h90e19122;
        rom_data0[15] = 12'h163; rom_data1[15] = 32'hf7d36428;
        rom_data0[16] = 12'h163; rom_data1[16] = 32'hfb8b546c;
        rom_data0[17] = 12'h9a2; rom_data1[17] = 32'hfb8b546c;
        rom_data0[18] = 12'h163; rom_data1[18] = 32'h9cd15860;
        rom_data0[19] = 12'h8a0; rom_data1[19] = 32'h706980a3;
        rom_data0[20] = 12'h9a0; rom_data1[20] = 32'hd4084b36;
        rom_data0[21] = 12'h8a1; rom_data1[21] = 32'h84e940a3;
        rom_data0[22] = 12'h7a1; rom_data1[22] = 32'h30498123;
        rom_data0[23] = 12'ha21; rom_data1[23] = 32'h20498123;
        rom_data0[24] = 12'h7a1; rom_data1[24] = 32'hf409d0a2;
        rom_data0[25] = 12'ha72; rom_data1[25] = 32'h1123642c;
        rom_data0[26] = 12'h0e8; rom_data1[26] = 32'hdb7b342c;
        rom_data0[27] = 12'h162; rom_data1[27] = 32'hfd2204ac;
        rom_data0[28] = 12'h173; rom_data1[28] = 32'he041c126;
        rom_data0[29] = 12'h7a2; rom_data1[29] = 32'h65832ca8;
        rom_data0[30] = 12'hb7c; rom_data1[30] = 32'h00e89126;
        rom_data0[31] = 12'h468; rom_data1[31] = 32'h489132e0;
        rom_data0[32] = 12'ha21; rom_data1[32] = 32'h84c9c1a6;
        rom_data0[33] = 12'h561; rom_data1[33] = 32'h7069d326;
        rom_data0[34] = 12'ha61; rom_data1[34] = 32'h64a01226;
        rom_data0[35] = 12'h0e3; rom_data1[35] = 32'h548981a3;
        rom_data0[36] = 12'hcc1; rom_data1[36] = 32'h84e940a3;
        rom_data0[37] = 12'h7b2; rom_data1[37] = 32'h631324a8;
        rom_data0[38] = 12'ha21; rom_data1[38] = 32'h84e8c1a2;
        rom_data0[39] = 12'ha21; rom_data1[39] = 32'h806191a6;
        rom_data0[40] = 12'ha21; rom_data1[40] = 32'h80e8c122;
        rom_data0[41] = 12'h7a1; rom_data1[41] = 32'h64015326;
        rom_data0[42] = 12'h172; rom_data1[42] = 32'he81132e0;
        rom_data0[43] = 12'h463; rom_data1[43] = 32'h54084382;
        rom_data0[44] = 12'ha20; rom_data1[44] = 32'h7049d326;
        rom_data0[45] = 12'ha66; rom_data1[45] = 32'h1460c122;
        rom_data0[46] = 12'ha20; rom_data1[46] = 32'h74e880a7;
        rom_data0[47] = 12'h7a0; rom_data1[47] = 32'h74e880a7;
        rom_data0[48] = 12'h461; rom_data1[48] = 32'h606980a3;
        rom_data0[49] = 12'h163; rom_data1[49] = 32'h548981a3;
        rom_data0[50] = 12'h7a1; rom_data1[50] = 32'he48981a3;
        rom_data0[51] = 12'ha21; rom_data1[51] = 32'hb48981a3;
        rom_data0[52] = 12'ha61; rom_data1[52] = 32'h34e8c1a2;
        rom_data0[53] = 12'h9a1; rom_data1[53] = 32'h80e8c1a2;
        rom_data0[54] = 12'h366; rom_data1[54] = 32'h106083a2;
        rom_data0[55] = 12'h461; rom_data1[55] = 32'h90e8c122;
        rom_data0[56] = 12'ha63; rom_data1[56] = 32'h88e15220;
        rom_data0[57] = 12'h168; rom_data1[57] = 32'h183800a4;
        rom_data0[58] = 12'h8a1; rom_data1[58] = 32'h2448c382;
        rom_data0[59] = 12'ha21; rom_data1[59] = 32'h94688127;
        rom_data0[60] = 12'h9a1; rom_data1[60] = 32'h9049d326;
        rom_data0[61] = 12'hcc1; rom_data1[61] = 32'hb06980a3;
        rom_data0[62] = 12'ha23; rom_data1[62] = 32'h00a050a4;
        rom_data0[63] = 12'h0f0; rom_data1[63] = 32'h30a058a4;
    end

    // ROM read logic
    reg [2:0] slot;
    reg [31:0] base;
    reg [15:0] clvd_base;
    
    always @(*) begin
        // Pause detection
        pause = !(p_rom == 6'h03 || p_rom == 6'h3e);
        
        // Slot selection based on ROM enables
        slot = 3'b111; // Invalid slot
        if (!rom_hsel_f1)  slot = 3'd0;
        if (!rom_hsel_va)  slot = 3'd1;
        if (!rom_hsel_f2)  slot = 3'd2;
        if (!rom_hsel_fc)  slot = 3'd3;
        if (!rom_hsel_f2q) slot = 3'd4;
        if (!rom_hsel_f3)  slot = 3'd5;
        if (!rom_hsel_fa)  slot = 3'd6;
    end
    
    // Parameter extraction
    always @(*) begin
        if (slot == 3'b111) begin
            rom_param = 4'b0;
        end else begin
            base = rom_data1[p_rom] >> slot;
            rom_param = {(base & 32'h000001) ? 1'b1 : 1'b0,
                        (base & 32'h000080) ? 1'b1 : 1'b0,
                        (base & 32'h004000) ? 1'b1 : 1'b0,
                        (base & 32'h200000) ? 1'b1 : 1'b0};
        end
    end
    
    // CLVD extraction
    always @(*) begin
        if (slot != 3'd0 && slot != 3'd6) begin
            rom_clvd = 4'hf;
        end else begin
            clvd_base = (rom_data1[p_rom] >> 28) | (rom_data0[p_rom] << 4);
            if (slot == 3'd6)
                clvd_base = clvd_base >> 1;
            rom_clvd = {(clvd_base & 16'h01) ? 1'b1 : 1'b0,
                       (clvd_base & 16'h04) ? 1'b1 : 1'b0,
                       (clvd_base & 16'h10) ? 1'b1 : 1'b0,
                       (clvd_base & 16'h40) ? 1'b1 : 1'b0};
        end
    end
    
    // Other ROM outputs
    always @(*) begin
        rom_cl = rom_data0[p_rom][4]; // Bit 4 of rom_data0
        
        rom_duration = {(rom_data0[p_rom] & 12'h020) ? 1'b1 : 1'b0,  // Bit 5 -> 6
                       (rom_data0[p_rom] & 12'h040) ? 1'b1 : 1'b0,   // Bit 6 -> 5
                       (rom_data0[p_rom] & 12'h080) ? 1'b1 : 1'b0,   // Bit 7 -> 4
                       (rom_data0[p_rom] & 12'h100) ? 1'b1 : 1'b0,   // Bit 8 -> 3
                       (rom_data0[p_rom] & 12'h200) ? 1'b1 : 1'b0,   // Bit 9 -> 2
                       (rom_data0[p_rom] & 12'h400) ? 1'b1 : 1'b0,   // Bit 10 -> 1
                       (rom_data0[p_rom] & 12'h800) ? 1'b1 : 1'b0};  // Bit 11 -> 0
    end
    
    // ROM parameter muxer logic (rom_param_muxer function)
    always @(*) begin
        rom_muxed_fx_out = 1'b0;
        
        // Complex muxing logic based on GTSR state and ROM parameters
        if ((!gtsr[1] && !gtsr[3] && !gtsr[5]) ||
            (!(rom_param[0]) && gtsr[1] && !gtsr[3] && !gtsr[5]) ||
            (!(rom_param[1]) && !gtsr[1] && gtsr[3] && !gtsr[5]) ||
            (!(rom_param[2]) && gtsr[1] && !gtsr[3] && gtsr[5]) ||
            (!(rom_param[3]) && gtsr[1] && gtsr[3] && !gtsr[5]) ||
            (gtsr[1] && gtsr[3] && gtsr[5]) ||
            (!gtsr[1] && gtsr[3] && gtsr[5]) ||
            (!gtsr[1] && !gtsr[3] && gtsr[5])) begin
            rom_muxed_fx_out = 1'b1;
        end
    end

endmodule
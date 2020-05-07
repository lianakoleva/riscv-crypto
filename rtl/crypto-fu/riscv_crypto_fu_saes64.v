
//
// module: riscv_crypto_fu_saes64
//
//  Implements the scalar 64-bit AES instructions for the RISC-V
//  cryptography extension
//
//  The following table shows which instructions are implemented
//  based on the selected value of XLEN, and the feature enable
//  parameter name(s).
//
//  Instruction     | XLEN=32 | XLEN=64 | Feature Parameter 
//  ----------------|---------|---------|----------------------------------
//   saes64.ks1     |         |    x    |
//   saes64.ks2     |         |    x    |
//   saes64.imix    |         |    x    | SAES_DEC_EN
//   saes64.encs    |         |    x    |
//   saes64.encsm   |         |    x    |
//   saes64.decs    |         |    x    | SAES_DEC_EN
//   saes64.decsm   |         |    x    | SAES_DEC_EN
//
module riscv_crypto_fu_saes64 #(
parameter SAES_DEC_EN = 1 , // Enable the saes64 decrypt instructions.
parameter SAES64_SBOXES = 8   // saes64 sbox instances. Valid values: 8
)(

input  wire         g_clk           , // Global clock
input  wire         g_resetn        , // Synchronous active low reset.

input  wire         valid           , // Are the inputs valid?
input  wire [ 63:0] rs1             , // Source register 1
input  wire [ 63:0] rs2             , // Source register 2
input  wire [  3:0] enc_rcon        , // rcon immediate for ks1 instruction

input  wire         op_saes64_ks1   , // RV64 AES Encrypt KeySchedule 1
input  wire         op_saes64_ks2   , // RV64 AES Encrypt KeySchedule 2
input  wire         op_saes64_imix  , // RV64 AES Decrypt KeySchedule Mix
input  wire         op_saes64_encs  , // RV64 AES Encrypt SBox
input  wire         op_saes64_encsm , // RV64 AES Encrypt SBox + MixCols
input  wire         op_saes64_decs  , // RV64 AES Decrypt SBox
input  wire         op_saes64_decsm , // RV64 AES Decrypt SBox + MixCols

output wire [ 63:0] rd              , // output destination register value.
output wire         ready             // Compute finished?

);

// Select I'th byte of X.
`define BY(X,I) X[7+8*I:8*I]

// Always finish in a single cycle.
assign     ready            = valid              ;

// AES Round Constants
wire [ 7:0] rcon [0:15];
assign rcon[ 0] = 8'h01; assign rcon[ 8] = 8'h1b;
assign rcon[ 1] = 8'h02; assign rcon[ 9] = 8'h36;
assign rcon[ 2] = 8'h04; assign rcon[10] = 8'h00;
assign rcon[ 3] = 8'h08; assign rcon[11] = 8'h00;
assign rcon[ 4] = 8'h10; assign rcon[12] = 8'h00;
assign rcon[ 5] = 8'h20; assign rcon[13] = 8'h00;
assign rcon[ 6] = 8'h40; assign rcon[14] = 8'h00;
assign rcon[ 7] = 8'h80; assign rcon[15] = 8'h00;


//
// Shift Rows
// ------------------------------------------------------------

wire [31:0] row_0   = {`BY(rs1,0),`BY(rs1,4),`BY(rs2,0),`BY(rs2,4)};
wire [31:0] row_1   = {`BY(rs1,1),`BY(rs1,5),`BY(rs2,1),`BY(rs2,5)};
wire [31:0] row_2   = {`BY(rs1,2),`BY(rs1,6),`BY(rs2,2),`BY(rs2,6)};
wire [31:0] row_3   = {`BY(rs1,3),`BY(rs1,7),`BY(rs2,3),`BY(rs2,7)};

// Forward shift rows
wire [31:0] fsh_0   =  row_0;                      
wire [31:0] fsh_1   = {row_1[23: 0], row_1[31:24]};
wire [31:0] fsh_2   = {row_2[15: 0], row_2[31:16]};
wire [31:0] fsh_3   = {row_3[ 7: 0], row_3[31: 8]};

// Inverse shift rows
wire [31:0] ish_0   =  row_0;
wire [31:0] ish_1   = {row_1[ 7: 0], row_1[31: 8]};
wire [31:0] ish_2   = {row_2[15: 0], row_2[31:16]};
wire [31:0] ish_3   = {row_3[23: 0], row_3[31:24]};

//
// Re-construct columns from rows
wire [31:0] f_col_1 = {`BY(fsh_3,2),`BY(fsh_2,2),`BY(fsh_1,2),`BY(fsh_0,2)};
wire [31:0] f_col_0 = {`BY(fsh_3,3),`BY(fsh_2,3),`BY(fsh_1,3),`BY(fsh_0,3)};

wire [31:0] i_col_1 = {`BY(ish_3,2),`BY(ish_2,2),`BY(ish_1,2),`BY(ish_0,2)};
wire [31:0] i_col_0 = {`BY(ish_3,3),`BY(ish_2,3),`BY(ish_1,3),`BY(ish_0,3)};

//
// Hi/Lo selection

wire [63:0] shiftrows_enc = {f_col_1, f_col_0};
wire [63:0] shiftrows_dec = {i_col_1, i_col_0};

//
// SubBytes
// ------------------------------------------------------------

//
// SBox input/output
wire [ 7:0] sb_fwd_out_0, sb_fwd_out_1, sb_fwd_out_2, sb_fwd_out_3;
wire [ 7:0] sb_fwd_out_4, sb_fwd_out_5, sb_fwd_out_6, sb_fwd_out_7;

wire [ 7:0] sb_inv_out_0, sb_inv_out_1, sb_inv_out_2, sb_inv_out_3;
wire [ 7:0] sb_inv_out_4, sb_inv_out_5, sb_inv_out_6, sb_inv_out_7;

//
// KeySchedule 1 SBox input selection
wire        rcon_rot    = enc_rcon != 4'hA;
wire [ 7:0] rconst      = rcon_rot ? rcon[enc_rcon] : 8'b0;

wire [ 7:0] ks1_sb3     = rcon_rot ? rs1[39:32] : rs1[63:56];
wire [ 7:0] ks1_sb2     = rcon_rot ? rs1[63:56] : rs1[55:48];
wire [ 7:0] ks1_sb1     = rcon_rot ? rs1[55:48] : rs1[47:40];
wire [ 7:0] ks1_sb0     = rcon_rot ? rs1[47:40] : rs1[39:32];

wire [31:0] ks1_sbout   = e_sbout[31:0] ^ {24'b0, rconst};

// If just doing sub-bytes, sbox inputs direct from rs1.
wire [ 7:0] sb_fwd_in_0 = op_saes64_ks1 ? ks1_sb0 : `BY(shiftrows_enc, 0);
wire [ 7:0] sb_fwd_in_1 = op_saes64_ks1 ? ks1_sb1 : `BY(shiftrows_enc, 1);
wire [ 7:0] sb_fwd_in_2 = op_saes64_ks1 ? ks1_sb2 : `BY(shiftrows_enc, 2);
wire [ 7:0] sb_fwd_in_3 = op_saes64_ks1 ? ks1_sb3 : `BY(shiftrows_enc, 3);
wire [ 7:0] sb_fwd_in_4 =                           `BY(shiftrows_enc, 4);
wire [ 7:0] sb_fwd_in_5 =                           `BY(shiftrows_enc, 5);
wire [ 7:0] sb_fwd_in_6 =                           `BY(shiftrows_enc, 6);
wire [ 7:0] sb_fwd_in_7 =                           `BY(shiftrows_enc, 7);

wire [ 7:0] sb_inv_in_0 = `BY(shiftrows_dec, 0);
wire [ 7:0] sb_inv_in_1 = `BY(shiftrows_dec, 1);
wire [ 7:0] sb_inv_in_2 = `BY(shiftrows_dec, 2);
wire [ 7:0] sb_inv_in_3 = `BY(shiftrows_dec, 3);
wire [ 7:0] sb_inv_in_4 = `BY(shiftrows_dec, 4);
wire [ 7:0] sb_inv_in_5 = `BY(shiftrows_dec, 5);
wire [ 7:0] sb_inv_in_6 = `BY(shiftrows_dec, 6);
wire [ 7:0] sb_inv_in_7 = `BY(shiftrows_dec, 7);

// Decrypt sbox output
wire [63:0] d_sbout     = {
    sb_inv_out_7, sb_inv_out_6, sb_inv_out_5, sb_inv_out_4,
    sb_inv_out_3, sb_inv_out_2, sb_inv_out_1, sb_inv_out_0 
};

// Encrypt sbox output
wire [63:0] e_sbout     = {
    sb_fwd_out_7, sb_fwd_out_6, sb_fwd_out_5, sb_fwd_out_4,
    sb_fwd_out_3, sb_fwd_out_2, sb_fwd_out_1, sb_fwd_out_0 
};

//
// MixColumns
// ------------------------------------------------------------

// Forward MixColumns inputs.
wire [31:0] mix_enc_i0  =                               e_sbout[31: 0];
wire [31:0] mix_enc_i1  =                               e_sbout[63:32];

// Inverse MixColumns inputs.
wire [31:0] mix_dec_i0  = op_saes64_imix ? rs1[31: 0] : d_sbout[31: 0];
wire [31:0] mix_dec_i1  = op_saes64_imix ? rs1[63:32] : d_sbout[63:32];

// Forward MixColumns outputs.
wire [31:0] mix_enc_o0  ;
wire [31:0] mix_enc_o1  ;

// Inverse MixColumns outputs.
wire [31:0] mix_dec_o0  ;
wire [31:0] mix_dec_o1  ;


//
// Result gathering
// ------------------------------------------------------------

wire [63:0] result_ks1  = {ks1_sbout, ks1_sbout};

wire [63:0] result_ks2  = {
    rs1[63:32] ^ rs2[63:32] ^ rs2[31:0] ,
    rs1[63:32] ^ rs2[63:32]
};

wire        mix         = op_saes64_encsm || op_saes64_decsm        ;

wire [63:0] result_enc  = mix ? {mix_enc_o1, mix_enc_o0} : e_sbout  ;

wire [63:0] result_dec  = mix ? {mix_dec_o1, mix_dec_o0} : d_sbout  ;

wire [63:0] result_imix =       {mix_dec_o1, mix_dec_o0}            ;

wire        op_enc      = op_saes64_encs || op_saes64_encsm;
wire        op_dec      = op_saes64_decs || op_saes64_decsm;

assign rd = 
    {64{op_saes64_ks1          }} & result_ks1     |
    {64{op_saes64_ks2          }} & result_ks2     |
    {64{op_enc                 }} & result_enc     |
    {64{op_dec                 }} & result_dec     |
    {64{op_saes64_imix         }} & result_imix    ;

//
// AES SBox instances
// ------------------------------------------------------------

riscv_crypto_aes_fwd_sbox i_fwd_sbox_0 (.in(sb_fwd_in_0),.fx(sb_fwd_out_0));
riscv_crypto_aes_fwd_sbox i_fwd_sbox_1 (.in(sb_fwd_in_1),.fx(sb_fwd_out_1));
riscv_crypto_aes_fwd_sbox i_fwd_sbox_2 (.in(sb_fwd_in_2),.fx(sb_fwd_out_2));
riscv_crypto_aes_fwd_sbox i_fwd_sbox_3 (.in(sb_fwd_in_3),.fx(sb_fwd_out_3));
riscv_crypto_aes_fwd_sbox i_fwd_sbox_4 (.in(sb_fwd_in_4),.fx(sb_fwd_out_4));
riscv_crypto_aes_fwd_sbox i_fwd_sbox_5 (.in(sb_fwd_in_5),.fx(sb_fwd_out_5));
riscv_crypto_aes_fwd_sbox i_fwd_sbox_6 (.in(sb_fwd_in_6),.fx(sb_fwd_out_6));
riscv_crypto_aes_fwd_sbox i_fwd_sbox_7 (.in(sb_fwd_in_7),.fx(sb_fwd_out_7));

generate if(SAES_DEC_EN) begin : saes64_dec_sboxes_implemented

riscv_crypto_aes_inv_sbox i_inv_sbox_0 (.in(sb_inv_in_0),.fx(sb_inv_out_0));
riscv_crypto_aes_inv_sbox i_inv_sbox_1 (.in(sb_inv_in_1),.fx(sb_inv_out_1));
riscv_crypto_aes_inv_sbox i_inv_sbox_2 (.in(sb_inv_in_2),.fx(sb_inv_out_2));
riscv_crypto_aes_inv_sbox i_inv_sbox_3 (.in(sb_inv_in_3),.fx(sb_inv_out_3));
riscv_crypto_aes_inv_sbox i_inv_sbox_4 (.in(sb_inv_in_4),.fx(sb_inv_out_4));
riscv_crypto_aes_inv_sbox i_inv_sbox_5 (.in(sb_inv_in_5),.fx(sb_inv_out_5));
riscv_crypto_aes_inv_sbox i_inv_sbox_6 (.in(sb_inv_in_6),.fx(sb_inv_out_6));
riscv_crypto_aes_inv_sbox i_inv_sbox_7 (.in(sb_inv_in_7),.fx(sb_inv_out_7));

end else begin  : saes64_dec_sboxes_not_implemented

assign sb_inv_out_0 = 8'b0;
assign sb_inv_out_1 = 8'b0;
assign sb_inv_out_2 = 8'b0;
assign sb_inv_out_3 = 8'b0;
assign sb_inv_out_4 = 8'b0;
assign sb_inv_out_5 = 8'b0;
assign sb_inv_out_6 = 8'b0;
assign sb_inv_out_7 = 8'b0;

end endgenerate

//
// Mix Column Instances
//
//  These take an entire column word, and output the 32-bit result of the
//  (Inv)MixColumns function
//
// ------------------------------------------------------------

riscv_crypto_aes_mixcolumn_enc i_mix_e0(
    .col_in (mix_enc_i0),
    .col_out(mix_enc_o0)
);
riscv_crypto_aes_mixcolumn_enc i_mix_e1(
    .col_in (mix_enc_i1),
    .col_out(mix_enc_o1)
);

generate if(SAES_DEC_EN) begin : saes64_dec_mix_columns_implemented

riscv_crypto_aes_mixcolumn_dec i_mix_d0(
    .col_in (mix_dec_i0),
    .col_out(mix_dec_o0)
);
riscv_crypto_aes_mixcolumn_dec i_mix_d1(
    .col_in (mix_dec_i1),
    .col_out(mix_dec_o1)
);

end else begin : saes64_dec_mix_columns_implemented

assign mix_dec_o0 = 32'b0;
assign mix_dec_o1 = 32'b0;

end endgenerate

`undef BY

endmodule

module apb_slave (
  input  logic        pclk,
  input  logic        presetn,
  input  logic [31:0] paddr,
  input  logic        pwrite,
  input  logic        psel,
  input  logic        penable,
  input  logic [31:0] pwdata,
  output logic [31:0] prdata,
  output logic        pready
);
  logic [31:0] mem [256];
  assign pready = 1'b1;
  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      for (int i = 0; i < 256; i++) mem[i] <= 32'h0;
      prdata <= 32'h0;
    end else if (psel && penable) begin
      if (pwrite) mem[paddr[7:0]] <= pwdata;
      else prdata <= mem[paddr[7:0]];
    end
  end
endmodule

interface apb_if(input logic pclk, input logic presetn);
  logic [31:0] paddr;
  logic        pwrite;
  logic        psel;
  logic        penable;
  logic [31:0] pwdata;
  logic [31:0] prdata;
  logic        pready;
endinterface
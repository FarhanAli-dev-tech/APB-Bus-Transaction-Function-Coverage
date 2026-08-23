class transaction;
  rand bit [31:0] addr;
  rand bit [31:0] data;
       bit [31:0] prdata;
  rand bit        write;

  constraint c_addr { addr inside {[0:255]}; }

  constraint c_data { 
    data dist {32'h0000_0000 := 5, 32'hFFFF_FFFF := 5, [1:32'hFFFF_FFFE] :/ 90}; 
  }
endclass

class generator;
  transaction t;
  mailbox mbx;
  event drv_done;

  bit [31:0] saved_addr [10];

  function new(mailbox mbx, event drv_done);
    this.mbx = mbx;
    this.drv_done = drv_done;
  endfunction

  task main();
    for (int i = 0; i < 10; i++) begin
      t = new();
      assert(t.randomize() with { write == 1'b1; });
      saved_addr[i] = t.addr;
      $display("[GEN] WRITE -> ADDR: 0x%0h | DATA: 0x%0h", t.addr, t.data);
      mbx.put(t);
      @(drv_done);
    end

    for (int i = 0; i < 10; i++) begin
      t = new();
      assert(t.randomize() with { write == 1'b0; addr == saved_addr[i]; });
      $display("[GEN] READ  -> ADDR: 0x%0h", t.addr);
      mbx.put(t);
      @(drv_done);
    end
  endtask
endclass

class driver;
  transaction tc;
  mailbox mbx;
  virtual apb_if vif;
  event drv_done;

  function new(mailbox mbx, virtual apb_if vif, event drv_done);
    this.mbx = mbx;
    this.vif = vif;
    this.drv_done = drv_done;
  endfunction

  task main();
    vif.psel <= 0;
    vif.penable <= 0;

    forever begin
      mbx.get(tc);
      @(posedge vif.pclk);
      vif.psel    <= 1'b1;
      vif.penable <= 1'b0;
      vif.pwrite  <= tc.write;
      vif.paddr   <= tc.addr;
      vif.pwdata  <= tc.data;

      @(posedge vif.pclk);
      vif.penable <= 1'b1;

      @(posedge vif.pclk);
      while(!vif.pready) @(posedge vif.pclk);

      #1;
      if (!tc.write) tc.prdata = vif.prdata;

      vif.psel    <= 1'b0;
      vif.penable <= 1'b0;

      -> drv_done;
    end
  endtask
endclass

class monitor;
  mailbox mbx;
  virtual apb_if vif;
  transaction t;
  int read_count = 0;

  covergroup apb_cg;
    option.per_instance = 1;
    option.name = "apb_bus_cg";

    cp_write : coverpoint t.write {
      bins write = {1};
      bins read  = {0};
    }

    cp_addr_region : coverpoint t.addr {
      bins low_region    = {[0   : 63]};
      bins midlow_region = {[64  : 127]};
      bins midhi_region  = {[128 : 191]};
      bins high_region   = {[192 : 255]};
      illegal_bins out_of_range = default;
    }

    cp_data : coverpoint t.data {
      bins zero      = {32'h0000_0000};
      bins all_ones  = {32'hFFFF_FFFF};
      bins mid_range = default;
    }

    cx_write_region : cross cp_write, cp_addr_region;

    cx_write_data : cross cp_write, cp_data {
      ignore_bins read_data = binsof(cp_write.read);
    }
  endgroup

  function new(mailbox mbx, virtual apb_if vif);
    this.mbx = mbx;
    this.vif = vif;
    apb_cg = new();
  endfunction

  task main();
    forever begin
      @(posedge vif.pclk);
      if (vif.psel && vif.penable && vif.pready) begin
        #1;
        t = new();
        t.write  = vif.pwrite;
        t.addr   = vif.paddr;
        t.prdata = vif.prdata;

        if (!t.write) begin
          read_count++;
          if (read_count == 2 || read_count == 4) begin
            t.prdata = vif.prdata ^ 32'hFFFFFFFF;
          end
        end

        t.data = t.write ? vif.pwdata : t.prdata;

        apb_cg.sample();
        mbx.put(t);
      end
    end
  endtask

  function void report_coverage();
    $display("=====================================================");
    $display(" APB Functional Coverage Report");
    $display("=====================================================");
    $display(" Overall coverage      : %0.2f %%", apb_cg.get_coverage());
    $display(" cp_write coverage     : %0.2f %%", apb_cg.cp_write.get_coverage());
    $display(" cp_addr_region cov    : %0.2f %%", apb_cg.cp_addr_region.get_coverage());
    $display(" cp_data coverage      : %0.2f %%", apb_cg.cp_data.get_coverage());
    $display(" cx_write_region cross : %0.2f %%", apb_cg.cx_write_region.get_coverage());
    $display(" cx_write_data cross   : %0.2f %%", apb_cg.cx_write_data.get_coverage());
    $display("=====================================================");
  endfunction
endclass

class scoreboard;
  mailbox mbx;
  transaction tc;
  bit [31:0] ref_mem [256];
  int pass_count = 0;
  int fail_count = 0;

  function new(mailbox mbx);
    this.mbx = mbx;
    foreach(ref_mem[i]) ref_mem[i] = 32'h0;
  endfunction

  task main();
    forever begin
      mbx.get(tc);
      if (tc.write) begin
        ref_mem[tc.addr[7:0]] = tc.data;
        $display("[SCB] WRITE: Addr = 0x%0h, Data = 0x%0h", tc.addr, tc.data);
      end else begin
        if (ref_mem[tc.addr[7:0]] === tc.prdata) begin
          $display("[SCB] PASS: Addr = 0x%0h | Expected = 0x%0h | Actual = 0x%0h",
                    tc.addr, ref_mem[tc.addr[7:0]], tc.prdata);
          pass_count++;
        end else begin
          $display("[SCB] FAIL: Addr = 0x%0h | Expected = 0x%0h | Actual = 0x%0h",
                    tc.addr, ref_mem[tc.addr[7:0]], tc.prdata);
          fail_count++;
        end
        $display("[SCB] STATISTICS -> PASS: %0d | FAIL: %0d", pass_count, fail_count);
      end
    end
  endtask
endclass

class environment;
  generator gen;
  driver drv;
  monitor mon;
  scoreboard scb;

  mailbox mbx_gen_drv;
  mailbox mbx_mon_scb;
  event drv_done;
  virtual apb_if vif;

  function new(virtual apb_if vif);
    this.vif = vif;
    mbx_gen_drv = new();
    mbx_mon_scb = new();

    gen = new(mbx_gen_drv, drv_done);
    drv = new(mbx_gen_drv, vif, drv_done);
    mon = new(mbx_mon_scb, vif);
    scb = new(mbx_mon_scb);
  endfunction

  task main();
    fork
      gen.main();
      drv.main();
      mon.main();
      scb.main();
    join_any
  endtask

  function void report();
    mon.report_coverage();
  endfunction
endclass

module tb;
  logic pclk;
  logic presetn;

  initial begin
    pclk = 0;
    forever #5 pclk = ~pclk;
  end

  initial begin
    presetn = 0;
    #12 presetn = 1;
  end

  apb_if vif(pclk, presetn);
  apb_slave dut (
    .pclk    (vif.pclk),
    .presetn (vif.presetn),
    .paddr   (vif.paddr),
    .pwrite  (vif.pwrite),
    .psel    (vif.psel),
    .penable (vif.penable),
    .pwdata  (vif.pwdata),
    .prdata  (vif.prdata),
    .pready  (vif.pready)
  );

  environment env;

  initial begin
    env = new(vif);
    env.main();
  end

  initial begin
    $dumpfile("dump.vcd"); $dumpvars;
    #800;
    env.report();
    $finish;
  end
endmodule
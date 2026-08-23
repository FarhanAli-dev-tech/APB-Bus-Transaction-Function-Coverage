# APB Bus Transaction Testbench: Functional Coverage

A UVM-style verification environment, built without UVM: `transaction`, `generator`, `driver`, `monitor`, `scoreboard`, connected through mailboxes and an event, driving an `apb_slave` DUT through a virtual interface.

The generator writes to 10 random addresses, then reads back from those same 10 addresses, and the scoreboard checks read data against a local reference memory. The monitor intentionally corrupts the 2nd and 4th read (an XOR against the sampled data) to confirm the scoreboard actually catches mismatches instead of passing everything by default. Two of the ten reads show FAIL in the log; that's expected behavior, not a bug.

## Coverage Model

The covergroup lives inside the `monitor` class, sampled right after a transaction is fully populated, on each cycle where `psel && penable && pready` are all true:

- `cp_write` — read vs. write, 2 bins
- `cp_addr_region` — the 256-entry address space split into four range bins (`low`, `midlow`, `midhi`, `high`), with the theoretically-unreachable region marked `illegal_bins` rather than `default`, so a broken address constraint would surface as a simulator error instead of a silent gap
- `cp_data` — edge values (`0x0`, `0xFFFFFFFF`) as explicit bins, everything else falling into `mid_range`
- `cx_write_region` — cross of write/read against address region
- `cx_write_data` — cross of write/read against data value, with `ignore_bins` dropping the read side (data on a read is whatever came back from memory, not something worth crossing against)
## Coverage Techniques Left Out, and Why

A few approaches got considered and dropped, not because they're wrong in general, but because they don't fit this DUT:

- **Implicit bins** on `addr` or `data` — both are 32-bit, so leaving out explicit bins would have the tool try to generate one bin per value. Range bins avoid that.
- **Wildcard bins** — useful for checking bit-pattern requirements like address alignment. Nothing in this design has that kind of constraint.
- **Transition bins** — meant for tracking state machine sequences. The APB slave here doesn't expose any FSM states to the testbench, only the `psel`/`penable`/`pready` handshake, which the existing coverpoints already capture.
- **Event-triggered covergroups** (`@(posedge pclk)`) — this would sample every clock edge regardless of whether a valid transaction occurred, adding noise from idle cycles. Sampling manually, only when `psel && penable && pready` are all true, keeps the numbers meaningful.
- **`iff` qualifier** — functionally equivalent to the manual `if` check already gating the `sample()` call. Switching wouldn't change any result.

## `pready` and Wait States

The DUT hardcodes `assign pready = 1'b1;`, so it never generates a wait state. A coverpoint on wait-state behavior would sit at 0% forever, not because of a testbench gap, but because the DUT itself has no such path. That's a finding about the design, not something the coverage model needs to chase.

## Running It

Xcelium needs the coverage flag explicitly, or `get_coverage()` returns 0 with a `COVNSM` warning regardless of how the covergroup is written:

```
xrun -Q -unbuffered -timescale 1ns/1ns -sysv -access +rw -coverage functional design.sv testbench.sv
```

On EDA Playground, add `-coverage functional` to the Run Options field alongside the existing `-access +rw`.


waveform :
<img width="1047" height="181" alt="image" src="https://github.com/user-attachments/assets/f2e870ea-1c7a-472e-a4a7-2826cd548838" />

## Files

- `design.sv` — `apb_slave` and `apb_if`
- `testbench.sv` — `transaction`, `generator`, `driver`, `monitor` (with covergroup), `scoreboard`, `environment`, `tb`

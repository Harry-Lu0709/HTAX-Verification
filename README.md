# HTAX Crossbar Switch Verification

**SystemVerilog | UVM | SystemVerilog Assertions (SVA) | Packet-Level Scoreboard**

A Universal Verification Methodology (UVM) testbench for a four-port **HyperTransport Advanced X-Bar (HTAX)** crossbar switch. The project verifies that packets injected through a transmit (TX) interface reach the intended receive (RX) interface with the correct **destination port, virtual channel, length, and payload**.

The protocol overview below is based on *HyperTransport Advanced X-Bar (HTAX) Specification*, version 0.14, by Heiner Litz (Computer Architecture Group, University of Heidelberg). The **UVM architecture and file inventory are grounded in the supplied SystemVerilog sources**, with explicit notes wherever the uploaded files do not yet form a complete, connected build. The test descriptions also reference the Texas A&M University CSCE 616 HTAX lab workflow.

## Table of Contents

- [1. Overview](#1-overview)
- [2. HTAX Architecture](#2-htax-architecture)
- [3. Configurable Parameters](#3-configurable-parameters)
- [4. TX Interface Specification](#4-tx-interface-specification)
- [5. RX Interface Specification](#5-rx-interface-specification)
- [6. End-to-End Packet Transfer](#6-end-to-end-packet-transfer)
- [7. UVM Verification Environment](#7-uvm-verification-environment)
- [8. Scoreboard Design](#8-scoreboard-design)
- [9. Test Cases and Expected Results](#9-test-cases-and-expected-results)
- [10. Running the Simulation](#10-running-the-simulation)
- [11. Source File Inventory](#11-source-file-inventory)
- [12. Verification Scope and Notes](#12-verification-scope-and-notes)

## 1. Overview

HTAX is a configurable, protocol-agnostic crossbar switch for communication among hardware endpoints, called **functional units (FUs)**. It can be used as an interconnect component in a Network-on-Chip (NoC), but a single HTAX switch is **not necessarily a complete NoC**.

Each HTAX port is bidirectional and exposes two distinct interfaces:

- **TX (transmit):** An external FU injects a packet into HTAX through its TX interface.
- **RX (receive):** HTAX forwards a packet to an external FU through that FU's RX interface.

A packet sent from FU 0 to FU 3 follows this path:

```text
FU 0 -> Port 0 TX -> HTAX arbitration / switch fabric -> Port 3 RX -> FU 3
```

The transmitter selects a destination **output port** and requests one or more **virtual channels (VCs)**. The crossbar handles contention and coordinates the transfers. The receiver participates in VC-level flow control by issuing receive-side grants.

The HTAX specification describes a scalable design with configurable port count, VC count, bus width, and optional buffering-related capabilities. The verification environment documented here targets the **four-port classroom configuration**, not every optional architectural feature.

## 2. HTAX Architecture

### Complete four-port system (ASCII block diagram)

```text
                        +-----------------------------------------+
+-----------------+     |               HTAX SWITCH               |     +-----------------+
| External FU 0   |     |                                         |     | External FU 2   |
|                 | TX->| [Port 0 TX]                 [Port 2 TX] |<-TX |                 |
|                 |<-RX | [Port 0 RX]                 [Port 2 RX] | RX->|                 |
+-----------------+     |                                         |     +-----------------+
                        |         +---------------------+         |
                        |         |  VC-aware control   |         |
                        |         |  Inport / outport   |         |
                        |         |    arbitration      |         |
                        |         |   Switch fabric     |         |
                        |         +---------------------+         |
+-----------------+     |                                         |     +-----------------+
| External FU 1   |     |                                         |     | External FU 3   |
|                 | TX->| [Port 1 TX]                 [Port 3 TX] |<-TX |                 |
|                 |<-RX | [Port 1 RX]                 [Port 3 RX] | RX->|                 |
+-----------------+     +-----------------------------------------+     +-----------------+

Legend: TX = FU -> HTAX (injection); RX = HTAX -> FU (delivery).
```

**Important:** TX and RX refer to the interface directions from the **external FU's perspective**. Both belong to the same bidirectional HTAX port; they are not separate endpoint devices. The diagram is a conceptual illustration, not a gate-level or cycle-accurate representation of HTAX internals.

### Example: Port 0 to Port 3

```text
   Sender                             HTAX                          Receiver
+----------+     +-------------+   +-------------------+   +-------------+    +----------+
|   FU 0   | --> |  Port 0 TX  |-->| Switching /       |-->|  Port 3 RX  |--> |   FU 3   |
|          |     |             |   | arbitration       |   |             |    |          |
+----------+     +-------------+   +-------------------+   +-------------+    +----------+

            Destination = Port 3; selected VC and payload remain associated with the packet.
```

**Routing distinction:** HTAX is described as *protocol-agnostic*. Routing interpretation of higher-level message contents is the responsibility of logic associated with the sending endpoint; the TX interface explicitly requests the destination through `tx_outport_req`. HTAX must arbitrate and switch the selected port/VC rather than independently decode application-level packet contents.

## 3. Configurable Parameters

| Parameter | Meaning | Implication |
|---|---|---|
| `PORTS` | Number of bidirectional HTAX ports | Determines the number of TX/RX interfaces and width of `tx_outport_req` |
| `VC` | Number of supported virtual channels | Determines the width of VC request, grant, and SOT vectors |
| `WIDTH` | Width of the payload bus, in bits | Determines the width of `tx_data` and `rx_data` |

The supplied `htax_defines.sv` configures **`PORTS = 4`, `VC = 2`, and `WIDTH = 64`**. Thus, the four TX interfaces and four RX interfaces each have a 64-bit data bus and 2-bit VC request/grant/SOT vectors. These are compile-time configuration macros in this lab, rather than fixed limits of the HTAX specification.

### Virtual channels

A **virtual channel (VC)** identifies the logical traffic channel associated with a packet. Multiple VCs allow the interconnect and receiving FU to distinguish different traffic classes. HTAX uses VC-aware requests and grants to support arbitration, quality of service, and deadlock avoidance.

In this build (`VC = 2`), for example:

```systemverilog
tx_vc_req = 2'b10; // Request VC 1
rx_sot    = 2'b10; // Received packet starts on VC 1
```

A `*_sot` vector identifies **one** active VC for the packet (one-hot); request/grant vectors may indicate **multiple** VCs.

## 4. TX Interface Specification

The TX interface is the ingress path from an external FU into HTAX. It includes request/grant control and packet data framing.

### TX signal reference

| Signal | Width | Direction | Description |
|---|---|---|---|
| `tx_outport_req` | `[PORTS-1:0]` | **FU -> HTAX** | One-hot request for the destination output port. A sender requests the output port to which the packet should be delivered. |
| `tx_vc_req` | `[VC-1:0]` | **FU -> HTAX** | Requests one or more virtual channels for the destination port. Must accompany the output-port request; at least one VC is requested while a port request is active. |
| `tx_vc_gnt` | `[VC-1:0]` | **HTAX -> FU** | Indicates which requested VC(s) have been granted. Multiple bits may be set; a grant indication is asserted for one clock cycle. |
| `tx_data` | `[WIDTH-1:0]` | **FU -> HTAX** | One payload data beat per transfer cycle. |
| `tx_sot` | `[VC-1:0]` | **FU -> HTAX** | **Start of transaction:** one-hot VC indication asserted alongside the first data beat. |
| `tx_eot` | `1 bit` | **FU -> HTAX** | **End of transaction:** asserted alongside the final data beat for one clock cycle. |
| `tx_release_gnt` | `1 bit` | **FU -> HTAX** | Releases the current grant / initiates re-arbitration, allowing arbitration for another transfer to overlap the current one. The specification describes it as a one-cycle pulse preceding `tx_eot`. |

### TX behavior

1. The external FU presents a one-hot destination request using `tx_outport_req` and selects requested VCs using `tx_vc_req`.
2. HTAX arbitrates access and returns the granted VC(s) on `tx_vc_gnt`.
3. The FU indicates the actual selected VC with `tx_sot` and presents the **first** beat on `tx_data` at the same time.
4. Additional data beats follow. The **last** beat is marked by `tx_eot`.
5. `tx_release_gnt` enables a new arbitration cycle before the current transfer fully completes, helping support closely spaced packets.

**Protocol subtleties:**

- `tx_outport_req` selects exactly one destination at a time, whereas `tx_vc_req` and `tx_vc_gnt` can select multiple VCs.
- Request/grant deassertion and overlap behavior follow the rules in the HTAX v0.14 specification; a new request must not be confused with the packet currently in flight.
- The specification also defines a **minimum-latency feature (MLF)**: under its one-VC-request restriction, TX may present `tx_sot` and the first data beat before the conventional post-grant start, allowing a beat to be captured with the grant.
- HTAX additionally specifies a **burst mode** in which one grant can cover multiple SOT/EOT-framed packets. This does **not** imply that all classroom test cases exercise burst mode.

### Illustrative TX request

```systemverilog
// Example for this build: PORTS=4, VC=2, destination Port 3, VC 1.
tx_outport_req = 4'b1000;
tx_vc_req      = 2'b10;

// After the appropriate grant/handshake:
tx_sot         = 2'b10;  // First beat; selected VC is 1
// tx_data carries first, middle, and final beats on successive transfer cycles.
// tx_eot marks the final beat.
```

## 5. RX Interface Specification

The RX interface is the egress path from HTAX to the destination external FU. The receiver controls which virtual channels it is ready to accept.

### RX signal reference

| Signal | Width | Direction | Description |
|---|---|---|---|
| `rx_vc_req` | `[VC-1:0]` | **HTAX -> FU** | Announces pending packets requesting service on one or more virtual channels. |
| `rx_vc_gnt` | `[VC-1:0]` | **FU -> HTAX** | Indicates which VC(s) the receiving FU is willing to accept. Multiple bits may be asserted. A grant can be made ahead of a request; once asserted, it must be maintained according to the RX handshake rules until the transaction starts. |
| `rx_data` | `[WIDTH-1:0]` | **HTAX -> FU** | Payload beat delivered to the receiving FU. |
| `rx_sot` | `[VC-1:0]` | **HTAX -> FU** | **Start of transaction:** one-hot VC indication asserted with the first received data beat. |
| `rx_eot` | `1 bit` | **HTAX -> FU** | **End of transaction:** asserted with the final received data beat for one clock cycle. |

### RX behavior

1. HTAX indicates pending VC traffic through `rx_vc_req`.
2. The receiving FU grants capacity for one or more VCs through `rx_vc_gnt`.
3. HTAX delivers the first beat with `rx_sot`, identifying the VC selected for the packet.
4. Further `rx_data` beats arrive on subsequent transfer cycles.
5. `rx_eot` identifies the **last beat**, which must still be captured by a monitor or receiving FU.

**Key distinction:** The **RX monitor** in this UVM project is passive; it **does not drive** `rx_vc_gnt`. Receive-side grant behavior must be supplied by the receiving-FU model or other testbench logic.

### Packet framing example

```text
Sample                0         1         2         3
rx_sot              VC 1        0         0         0
rx_data              D0        D1        D2        D3
rx_eot                0         0         0         1

Reconstructed transaction:
  vc     = 1
  length = 4
  data   = [D0, D1, D2, D3]
```

The SOT beat and EOT beat **both count** toward packet length. The classroom RX monitor samples signals at the **falling clock edge** because the HTAX changes its RX outputs at the rising edge; this reduces testbench/DUT race conditions.

### System interface

The HTAX specification also identifies a system clock (`clk`) and an active-low reset (`res_n`). These are **system-level** signals, not TX or RX data-path signals. Exact HDL port names should be checked against the particular DUT wrapper in the repository.

## 6. End-to-End Packet Transfer

Consider a packet sent from **FU 0 / TX Port 0** to **FU 3 / RX Port 3**, using **VC 1**:

```text
External FU 0                 HTAX crossbar                  External FU 3
     |                              |                              |
     |-- TX outport/VC request ---->|                              |
     |<------ TX VC grant ----------|                              |
     |                              |------ RX VC request -------->|
     |                              |<-------- RX VC grant --------|
     |-- TX SOT + first data ------>|                              |
     |-- TX data beats ------------>|-- RX SOT + data beats ------>|
     |-- TX EOT + final data ------>|-- RX EOT + final data ------>|
     |                              |                              |
```

This diagram shows **logical dependencies, not fixed clock-cycle alignment**. TX and RX activity may be separated in time by arbitration, grant timing, implementation latency, or buffering. In particular, the first TX beat does not necessarily appear on the RX interface in the same cycle. The minimum-latency and overlapping-arbitration features can alter the detailed sequencing.

The intended observable outcome is:

- The packet arrives at **destination Port 3**, not another port.
- Its **VC**, **beat count**, and **payload** match the transmitted transaction.
- Packets targeting the same destination are checked against the corresponding **oldest outstanding expectation**, consistent with the lab's ordering model.

## 7. UVM Verification Environment

The source-driven testbench uses **four active TX agents**, **four passive RX agents**, and **one shared packet-level scoreboard**. The DUT-facing signal interfaces are instantiated in the SystemVerilog top-level module, while the UVM class hierarchy is assembled under `htax_env`. All data-path monitors sample on **negedges** (the testbench driver drives on posedges).

### 7.1 Top-level DUT and UVM component hierarchy

```text
SystemVerilog module top                         [htax_top.sv]
|
+-- clk, rst_n
+-- inst_htax_top : htax_top                     [HTAX DUT instance]
+-- inst_htax_tx_intf[0:3]                       [htax_tx_interface]
|     +-- TX protocol assertions (SVA)
+-- inst_htax_rx_intf[0:3]                       [htax_rx_interface]
|     +-- RX VC-grant stimulus logic
|     +-- RX protocol assertions (SVA)
+-- uvm_config_db::set(..., "tx_vif" / "rx_vif", ...)
+-- run_test()  --> UVM test                       [test_lib.svh referenced]
                     |
                     +-- tb : htax_env            [htax_env.sv]
                          |
                          +-- tx_port[0..3] : htax_tx_agent_c (UVM_ACTIVE)
                          |    +-- sequencer  : htax_sequencer_c
                          |    +-- tx_driver  : htax_tx_driver_c
                          |    +-- tx_monitor : htax_tx_monitor_c
                          |
                          +-- rx_port[0..3] : htax_rx_agent_c (UVM_PASSIVE)
                          |    +-- rx_monitor : htax_rx_monitor_c
                          |
                          +-- htax_sb : htax_scoreboard_c
                               +-- exp_q[0][$] ... exp_q[3][$]
                               +-- tx0_export ... tx3_export
                               +-- rx0_export ... rx3_export
```

The actual UVM test class and the `test_lib.svh` contents were **not among the supplied files**. The hierarchy above shows the `tb` environment and components defined in the uploaded sources; the name `tb` is also used by the lab's test-side hierarchy in the existing verification workflow.

### 7.2 End-to-end stimulus and checking paths

```text
  UVM TEST / SEQUENCE
  simple_random_seq (15 htax_packet_c items)
          |
          v
  +------------------------------------+
  |  ACTIVE TX AGENT [i], i = 0..3     |
  |                                    |
  |  htax_sequencer_c                  |
  |          | seq_item_export         |
  |          v                         |
  |  htax_tx_driver_c                  |
  |          |                         |
  |          | drives TX pins          |
  |          v                         |
  |  TX interface [i] --+              |
  |                     |              |
  |  htax_tx_monitor_c <-+ (observes)  |
  +---------------------|--------------+
                        | TX wires
                        v
          +-------------------------------+
          |            HTAX DUT           |
          |     four-port crossbar        |
          +---------------+---------------+
                          | RX wires
                          v
          +-------------------------------------+
          | RX interface [j], j = 0..3          |
          | - drives rx_vc_gnt (FU emulation)   |
          | - implements RX assertions         |
          |                                     |
          | PASSIVE RX AGENT [j]                |
          |   htax_rx_monitor_c (observes)      |
          +------------------+------------------+
                             |
                             | rx_collect_port.write(rx_mon_packet)
                             v
                       +-----------------+
                       |   SCOREBOARD    |
                       | rxj_export      |
                       | compare_pkt(j)  |
                       +-----------------+

 TX monitor [i] -- intended tx_collect_port.write(tx_mon_packet) -->
                  scoreboard.txi_export --> exp_q[dest_port].push_back(...)

 Note: The TX analysis path is connected in htax_env.sv, but the supplied
       htax_tx_monitor_c.sv does not yet declare/create/write tx_collect_port.
       See "Integration gap" below.
```

**Two separate communication mechanisms:** TX/RX interface signals are physical DUT connections. The monitor-to-scoreboard arrows are **UVM transaction-level analysis connections**: the monitors do not drive DUT data, and the scoreboard never forwards a real packet through the switch.

### 7.3 TX agents: active senders and passive observers

Every `htax_tx_agent_c` starts with `is_active = UVM_ACTIVE`. In `build_phase`, an active agent creates a `sequencer`, `tx_driver`, and `tx_monitor`; in `connect_phase`, it connects:

```systemverilog
tx_driver.seq_item_port.connect(sequencer.seq_item_export);
```

The TX driver receives each randomized `htax_packet_c` via `get_next_item(req)`, drives the TX pins on rising clock edges, then calls `item_done()`. It waits the randomized `delay`, requests the destination and VC mask, waits for a matching grant, selects one granted VC, drives the first beat with `tx_sot`, drives the remaining beats, asserts `tx_release_gnt` on the second-to-last beat and `tx_eot` on the last beat. A new packet is not driven until the previous item is complete. The separate TX monitor reconstructs a `htax_tx_mon_packet_c` by observing the granted destination, SOT/VC, and every beat through EOT at falling clock edges.

**TX transaction generation (`htax_packet_c.sv`):**

| Randomized field | Constraint in the uploaded source |
|---|---|
| `delay` | 1–20 cycles |
| `dest_port` | 0 through `PORTS-1` (0–3 here) |
| `vc` | Nonzero requested-VC **bit mask**, not a VC index |
| `length` | 3–63 beats; weighted ranges 3–15 (50), 16–47 (40), 48–63 (10) |
| `data[]` | `WIDTH`-bit dynamic array, `data.size() == length` |
| Short packets | `length <= 15` implies `$countones(vc) == 1` |

The uploaded `htax_seqs.sv` declares `htax_base_seq` (which raises/drops a phase objection when `starting_phase` is set) and `simple_random_seq`, which generates **15** items with `` `uvm_do(req) ``. Other test or sequence classes may be referenced by the lab, but their definitions were not in the supplied batch.

### 7.4 RX agents and the receiving-FU grant model

Each `htax_rx_agent_c` is **passive** (`is_active = UVM_PASSIVE`) and creates only `rx_monitor`. There is **no RX sequencer or RX driver** in the uploaded agent. Instead, `htax_rx_interface.sv` provides simple standalone grant-generation logic as part of the **SystemVerilog interface itself**:

```systemverilog
logic [VC-1:0] rx_vc_gnt = '0;
logic tran_on = 0;

always @(|rx_vc_req) begin
    wait (tran_on == 0);
    @(posedge clk);
    rx_vc_gnt = rx_vc_req;
end

always @(posedge (|rx_sot)) tran_on = 1;
always @(negedge rx_eot)    tran_on = 0;
```

This testbench-specific model waits for its transaction-active indication to clear before updating the grant at a clock edge. It is a simple FU emulator, **not** a full independent RX UVM agent and **not** a general-purpose credit/ready protocol model. In particular, the grant-update process triggers on changes to the reduction-OR of `rx_vc_req`, so it should not be described as responding to every possible per-bit change of the request vector.

The passive RX monitor detects a nonzero `rx_sot` at the falling edge, creates one `htax_rx_mon_packet_c`, stores the physical RX `port` and the one-hot `vc` index, appends each `rx_data` beat into a dynamic array **including the EOT beat**, and forwards the completed object using:

```systemverilog
rx_collect_port.write(rx_mon_packet);
```

### 7.5 Virtual interface configuration

The top module instantiates **four** TX interfaces and **four** RX interfaces, connects them to the DUT's `fu0`–`fu3` signals, and makes each interface available through `uvm_config_db`:

```systemverilog
uvm_config_db#(virtual htax_tx_interface)::set(
    null, "*tx_port[0]*", "tx_vif", inst_htax_tx_intf[0]);
uvm_config_db#(virtual htax_rx_interface)::set(
    null, "*rx_port[0]*", "rx_vif", inst_htax_rx_intf[0]);
// Equivalent assignments exist for ports 1, 2, and 3.
```

Each driver/monitor retrieves its corresponding handle during `build_phase` via `uvm_config_db::get()`. This allows one reusable agent class to operate on different physical interfaces without hard-coding hierarchical HDL paths.

### 7.6 UVM analysis connections and the scoreboard

`htax_env.sv` constructs the scoreboard as `htax_sb`. In its `connect_phase`, it specifies eight monitor-to-scoreboard connections (four TX and four RX). The four **RX connections are fully implemented** in the uploaded monitor and environment sources:

```systemverilog
rx_port[0].rx_monitor.rx_collect_port.connect(htax_sb.rx0_export);
rx_port[1].rx_monitor.rx_collect_port.connect(htax_sb.rx1_export);
rx_port[2].rx_monitor.rx_collect_port.connect(htax_sb.rx2_export);
rx_port[3].rx_monitor.rx_collect_port.connect(htax_sb.rx3_export);
```

For each received packet, the respective scoreboard `write_rxN_export()` calls `compare_pkt(N, rx_mon_packet)`. The environment also assigns `rx_port[i].rx_monitor.port = i` so the RX packet records the actual physical destination.

The environment **attempts** the corresponding four TX connections:

```systemverilog
tx_port[0].tx_monitor.tx_collect_port.connect(htax_sb.tx0_export);
// ... tx1_export, tx2_export, tx3_export
```

Each `txN_export` is an analysis implementation (`uvm_analysis_imp_txN_export`) whose `write_txN_export()` calls `push_to_queue()` to populate the expected-packet queue. The scoreboard defines all eight `write_*_export()` callback functions using the `uvm_analysis_imp_decl` macros.

> **Integration gap in the uploaded snapshot:** `htax_tx_monitor_c.sv` currently logs `TX_MON` but **does not declare, construct, or write to `tx_collect_port`**, despite the environment's references to it. As uploaded, that TX connection cannot compile. To complete the intended data path, add `uvm_analysis_port #(htax_tx_mon_packet_c) tx_collect_port;` to the TX monitor, construct it with `new("tx_collect_port", this)` in the constructor, and invoke `tx_collect_port.write(tx_mon_packet);` after the packet is reconstructed. Once applied, the intended TX→scoreboard path matches the diagram above. This README does not claim that fix was made to the supplied `.sv` file.

### 7.7 Interface-level assertions (SVA)

The uploaded SVA checkers are embedded **inside the SystemVerilog interfaces**, independent of the UVM scoreboard:

| Interface | Properties present in the uploaded code |
|---|---|
| `htax_tx_interface.sv` | One-hot destination request; mutual presence of outport/VC requests; grant subset of request; SOT/EOT after a grant; single-cycle EOT; release-grant timing; SOT after prior EOT; ordered request/grant/SOT/release/EOT transfer sequence |
| `htax_rx_interface.sv` | One-hot, one-cycle SOT; one-cycle EOT; RX VC grant held until its request/transaction-start condition |

These check **control-protocol behavior**. The scoreboard separately checks **end-to-end destination, VC, length, and payload**. A scoreboard pass alone does not prove every protocol assertion passed; inspect simulator assertion diagnostics as well as UVM severity counts.

### 7.8 RX monitor transaction reconstruction

The RX monitor's output transaction (`htax_rx_mon_packet_c`) includes:

| Field | Description |
|---|---|
| `port` | Physical RX port, set by the environment. |
| `vc` | Index of the asserted bit in `rx_sot`. |
| `length` | Number of observed `rx_data` beats, including SOT and EOT. |
| `data[]` | Dynamic array of `WIDTH`-bit beats, in receive order. |

```text
forever:
    wait for rx_sot != 0 on a falling clock edge
    create a new packet; assign port and decode VC
    do:
        append the current rx_data beat
        length++
        if rx_eot: stop gathering beats
        wait for the next falling edge
    print RX_MON summary
    rx_collect_port.write(packet)
```

## 8. Scoreboard Design

The scoreboard uses a **separate FIFO queue for each destination port**:

```systemverilog
// One queue per destination port; each queue stores TX monitor packet handles.
htax_tx_mon_packet_c exp_q[PORTS][$];
```

### Expected-packet insertion (TX side)

The **intended** flow is for every TX monitor to publish its completed packet through a UVM analysis port. The environment and scoreboard are already coded for this; the uploaded TX monitor still requires the analysis-port addition noted in Section 7.6. The scoreboard's TX write method uses the packet's `dest_port`:

```systemverilog
if (mon_pkt.dest_port < 0 || mon_pkt.dest_port >= PORTS) begin
    `uvm_error("SCOREBOARD", "Invalid destination port")
    return;
end
exp_q[mon_pkt.dest_port].push_back(mon_pkt);
```

### Actual-packet comparison (RX side)

Each RX monitor publishes a received packet. The scoreboard chooses the queue indexed by the **actual RX port**:

```text
RX packet arrives at port p
    |
    +-- exp_q[p] empty? YES --> report unexpected packet
    |
    +-- NO --> expected = exp_q[p].pop_front()
                  |
                  +-- compare expected.vc     vs received.vc
                  +-- compare expected.length vs received.length
                  +-- compare expected.data[] vs received.data[]
                  |
                  +-- report one mismatch error (show both packets), if different
```

In SystemVerilog, the queue's oldest item is removed using `pop_front()`. A comparison failure must **not** prevent that expected item from being removed; otherwise one bad packet could misalign all subsequent comparisons.

### End-of-test check

In `check_phase`, the scoreboard checks **all four queues**:

- An **empty queue** means that no expected packet remains unmatched for that destination.
- A **nonempty queue** means at least one transmitted packet was never matched by a received packet.
- **Empty queues alone are not proof of correctness:** the scoreboard must actually receive packets and perform comparisons, and the simulation must report no unexpected packets or mismatches.

The scoreboard's correctness therefore relies on **both** during-run comparison errors and end-of-run queue checks.

## 9. Test Cases and Expected Results

| Test | TX traffic | Expected packet count | Success criteria |
|---|---|---:|---|
| `simple_random_test` | Random packets injected on one TX port | 15 TX / 15 RX | All four expected queues empty; zero UVM errors/fatals; TX and RX packets match. |
| `multiport_test` | Random traffic on all four TX ports (15 per TX port in Lab 9) | 60 TX / 60 RX | All four expected queues empty; zero UVM errors/fatals; TX and RX packets match. |

### Previously observed log example: `simple_random_test`

The following is a **previously shared run summary**, not a newly executed simulation of the exact uploaded source snapshot (which has the TX-monitor integration gap described above):

```text
[TX_MON]    15 packets observed
[RX_MON]    15 packets observed
[SCOREBOARD] Port 0 Queue is empty
[SCOREBOARD] Port 1 Queue is empty
[SCOREBOARD] Port 2 Queue is empty
[SCOREBOARD] Port 3 Queue is empty
UVM_ERROR: 0
UVM_FATAL: 0
```

This result is consistent with a successful 15-packet run; the detailed TX/RX log comparison provides an additional check. The 60-packet case above is an **expected test target**, not a claimed measured result. The uploaded files include `simple_random_seq`, but **do not include** the definitions for `simple_random_test`, `multiport_test`, or the test library; those tests are referenced by the lab workflow rather than verified from this batch of sources.

> **Lab-specific note:** The assignment handout describes a possible known `assert_gnt_subset_of_req` assertion failure in `multiport_test`, related to the DUT granting a VC that it did not request. Review assertion reports separately rather than treating `UVM_ERROR = 0` as a guarantee that no assertions fired.

## 10. Running the Simulation

The CSCE 616 lab workflow uses Cadence Xcelium (`xrun`) on the course server. The following paths and scripts refer to the **lab setup**, not files present in the supplied upload. Ensure that the TX monitor analysis port is completed and that the test library and `run.f` are available before running:

```bash
source setupx.bash
cd work/sim

# Single-source random test
xrun -f run.f +UVM_TESTNAME=simple_random_test

# Multi-source random test
xrun -f run.f +UVM_TESTNAME=multiport_test
```

Each run rebuilds through the lab's `run.f` configuration. Run the tests separately; the second execution may overwrite `xrun.log`.

### Inspect monitor and scoreboard activity

```bash
# Count TX and RX monitor reports
grep -c '\[TX_MON\]' xrun.log
grep -c '\[RX_MON\]' xrun.log

# Review successful comparisons if scoreboard match logging is enabled
grep 'Packet matched' xrun.log

# Check both UVM and simulator assertion reports
grep -E 'UVM_ERROR|UVM_FATAL|\*E,ASRTST' xrun.log
```

### Compare complete TX and RX packet summaries

The TX and RX monitor classes emit equivalent packet-summary lines. Normalize their tags, sort the summaries, and compare:

```bash
grep 'UVM_INFO.*\[TX_MON\]' xrun.log | sed 's/.*\[TX_MON\] //' | sort > tx.txt
grep 'UVM_INFO.*\[RX_MON\]' xrun.log | sed 's/.*\[RX_MON\] //' | sort > rx.txt

wc -l tx.txt rx.txt
diff -u tx.txt rx.txt
```

Expected: **15 lines each** for `simple_random_test`, or **60 lines each** for `multiport_test`; `diff` should produce **no output**. Sorting checks identical packet summaries without assuming a global arrival order across different destination ports. The scoreboard separately checks FIFO order **within each destination**.

## 11. Source File Inventory

The following is the **exact logical inventory of the 17 SystemVerilog source files supplied for this README update**. The files were uploaded as individual files, so the list is organized by function rather than claiming a particular Git repository directory layout.

```text
Configuration and compilation
  htax_defines.sv           PORTS=4, VC=2, WIDTH=64
  htax_pkg.sv               UVM package and class includes
  htax_top.sv               Simulation top, DUT wiring, config_db, run_test()

DUT-facing interfaces and SVA
  htax_tx_interface.sv      TX signals and TX SVA
  htax_rx_interface.sv      RX signals, simple RX grant model, RX SVA

Sequences and transaction models
  htax_packet_c.sv          Randomized TX sequence item + constraints
  htax_seqs.sv              htax_base_seq and simple_random_seq
  htax_sequencer_c.sv       TX sequencer
  htax_tx_mon_packet_c.sv   Monitored TX packet representation
  htax_rx_mon_packet_c.sv   Monitored RX packet representation

UVM agent components
  htax_tx_agent_c.sv        Active TX agent (driver, sequencer, monitor)
  htax_tx_driver_c.sv       Drives the TX pins
  htax_tx_monitor_c.sv      Reconstructs TX packets (analysis port missing)
  htax_rx_agent_c.sv        Passive RX agent (monitor only)
  htax_rx_monitor_c.sv      Reconstructs RX packets and publishes them

Environment and checking
  htax_env.sv               4 TX agents + 4 RX agents + scoreboard connections
  htax_scoreboard_c.sv      Expected FIFOs and end-to-end packet comparisons
```

**Referenced but not supplied in this upload:** the actual DUT implementation (`htax_top` module), `test_lib.svh`, individual test class files (including `simple_random_test` and `multiport_test`), the simulator file list (`run.f`), and any course setup scripts. Accordingly, this document does not invent their implementation details or repository paths.

## 12. Verification Scope and Notes

### What this project checks

- Intended end-to-end checking of TX-to-RX packet delivery at the **requested destination** (after connecting the missing TX analysis port).
- Preservation of **VC**, **packet length**, and **payload data**.
- Order-aware matching through **per-destination FIFO queues**.
- Detection of **unexpected RX packets**, **content mismatches**, and **missing packets** at the end of simulation.
- TX/RX interface protocol properties through SVA already present in the supplied interface files, subject to compilation and assertion enablement.

### Important limitations

- **As uploaded, the TX monitor lacks `tx_collect_port`**, while `htax_env` references it; this must be corrected before compiling the integrated scoreboard topology. See Section 7.6.
- The uploaded bundle does not include the DUT implementation, UVM test definitions, or `run.f`, so the source snapshot was **not simulated as part of this README update**.
- A passing test demonstrates correctness for **tested stimulus and checked properties**, not exhaustive functional correctness.
- The exercise's scoreboard uses a **per-destination FIFO expectation model**; it does not model every optional HTAX buffering mode or every possible protocol feature.
- Packet data in the provided RX transaction class is a `bit [WIDTH-1:0] data[]` dynamic array (a **2-state** type). Unknown (`X`) or high-impedance (`Z`) values on DUT signals are not preserved when stored in that field; separate four-state interface checks/assertions are needed to catch them.
- The UVM RX monitor is **passive**. It verifies delivery but does not implement the external receiver's grant-generation behavior.
- The original HTAX v0.14 specification is marked **confidential**. It is **not included** in this repository. Confirm permission before publishing specification-derived information or source material in a public repository.

### References

- Heiner Litz, *HyperTransport Advanced X-Bar (HTAX) Specification*, v0.14, Computer Architecture Group, University of Heidelberg (reference document provided for coursework; not redistributed here).
- Texas A&M University, CSCE 616, *Lab 9 — HTAX RX Monitor and Scoreboard* (Fall 2026).

---

**Project focus:** Practical SystemVerilog/UVM verification of a multiport, VC-aware crossbar: pin-level stimulus and monitoring, transaction reconstruction, analysis-port communication, and end-to-end scoreboard checking.

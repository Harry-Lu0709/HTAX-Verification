# HTAX Crossbar Switch Verification

**SystemVerilog | UVM | Assertions | Packet-Level Scoreboard**

A Universal Verification Methodology (UVM) testbench for a four-port **HyperTransport Advanced X-Bar (HTAX)** crossbar switch. The project verifies that packets injected through a transmit (TX) interface reach the intended receive (RX) interface with the correct **destination port, virtual channel, length, and payload**.

The protocol overview below is based on *HyperTransport Advanced X-Bar (HTAX) Specification*, version 0.14, by Heiner Litz (Computer Architecture Group, University of Heidelberg). The verification workflow follows the Texas A&M University CSCE 616 HTAX lab assignments, including the RX monitor and scoreboard exercise.

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
- [11. Repository Structure](#11-repository-structure)
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

The lab environment uses **four ports (`PORTS = 4`)**. Other parameter values are build-time configuration choices; do not assume that an example bit pattern fixes the design's VC count or data width.

### Virtual channels

A **virtual channel (VC)** identifies the logical traffic channel associated with a packet. Multiple VCs allow the interconnect and receiving FU to distinguish different traffic classes. HTAX uses VC-aware requests and grants to support arbitration, quality of service, and deadlock avoidance.

For example, if `VC = 3`:

```systemverilog
tx_vc_req = 3'b010; // Request VC 1
rx_sot    = 3'b010; // Packet starts on VC 1
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
// Example only: PORTS=4, VC=3, destination Port 3, VC 1.
tx_outport_req = 4'b1000;
tx_vc_req      = 3'b010;

// After the appropriate grant/handshake:
tx_sot         = 3'b010;  // First beat; selected VC is 1
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

The verification environment stimulates the real HTAX DUT through TX pins, observes both sides, and checks the delivered packets against expected transactions.

```text
                     +------------------------------+
                     |          UVM TEST            |
                     | sequences / test scenarios   |
                     +---------------+--------------+
                                     |
                                     v
                     +------------------------------+
                     | TX sequencers + TX drivers   |
                     | Model external FU senders    |
                     +---------------+--------------+
                                     |
                                     v
                         TX interface signals
                                     |
                         +-----------+-----------+
                         |         HTAX DUT      |
                         |    4-port crossbar    |
                         +-----------+-----------+
                                     |
                          RX interface signals
                                     |
                             RX-side FU model
                           / grant control logic

            TX interfaces                        RX interfaces
                 |                                     |
                 v                                     v
       +--------------------+                +--------------------+
       | 4 x TX monitors    |                | 4 x RX monitors    |
       | observed requests, |                | reconstructed RX   |
       | VC and TX payload  |                | VC and RX payload  |
       +---------+----------+                +----------+---------+
                 |                                      |
                 | analysis_port.write()                | analysis_port.write()
                 v                                      v
       +--------------------------------------------------------+
       |                    UVM SCOREBOARD                      |
       |                                                        |
       | exp_q[0]  exp_q[1]  exp_q[2]  exp_q[3]                  |
       |  TX push_back(dest_port) -> RX pop_front(port)          |
       |  Compare: VC / length / all data beats                  |
       +--------------------------------------------------------+
```

> **Diagram note:** TX/RX monitors only observe DUT interface traffic. The arrows to the scoreboard represent **transaction-level UVM analysis connections**, not RTL data wires.

### UVM component responsibilities

| Component | Responsibility |
|---|---|
| **Test / sequences** | Generate traffic scenarios and coordinate simulation lifetime through UVM objections. |
| **TX sequencer** | Supplies randomized or directed packet transactions to the TX driver. |
| **TX driver** | Converts packet transactions into TX interface signal activity, acting as a sender FU. |
| **TX monitor** | Passively reconstructs packets injected into HTAX and publishes expected transactions. |
| **RX grant logic** | Models a receiver FU's willingness to accept VC traffic; separate from the passive RX monitor. |
| **RX monitor** | Passively reconstructs delivered packets from `rx_sot` through `rx_eot`, inclusive. |
| **Scoreboard** | Maintains per-destination expected queues and compares received packets to the oldest outstanding expectation. |
| **Protocol assertions** | Check TX/RX interface protocol requirements independently of end-to-end payload matching, when enabled. |

### RX monitor packet reconstruction

The RX monitor creates a new `htax_rx_mon_packet_c` object for each packet and records:

| Field | Description |
|---|---|
| `port` | The **RX port** where the packet was observed. |
| `vc` | Index of the asserted bit in `rx_sot`. |
| `length` | Number of observed `rx_data` beats, including SOT and EOT beats. |
| `data[]` | Dynamic array containing each beat in order. |

A typical algorithm is:

```text
forever:
    wait for rx_sot != 0 at the monitor's sampling edge
    create packet, set port and decode VC
    repeat:
        append current rx_data to packet.data[]
        increment packet.length
        if rx_eot == 1: stop collecting this packet
        wait for next sampling edge
    log packet and publish it through rx_collect_port
```

## 8. Scoreboard Design

The scoreboard uses a **separate FIFO queue for each destination port**:

```systemverilog
// One queue per destination port; each queue stores TX monitor packet handles.
htax_tx_mon_packet_c exp_q[PORTS][$];
```

### Expected-packet insertion (TX side)

Every TX monitor publishes a completed packet through a UVM analysis port. The scoreboard's TX write method uses the packet's `dest_port`:

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

### Example observed result: `simple_random_test`

A local simulation produced the following summary:

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

This result is consistent with a successful 15-packet run; the detailed TX/RX log comparison provides an additional check. The 60-packet case above is an **expected test target**, not a claimed measured result.

> **Lab-specific note:** The assignment handout describes a possible known `assert_gnt_subset_of_req` assertion failure in `multiport_test`, related to the DUT granting a VC that it did not request. Review assertion reports separately rather than treating `UVM_ERROR = 0` as a guarantee that no assertions fired.

## 10. Running the Simulation

The CSCE 616 lab setup uses Cadence Xcelium (`xrun`) on the course server. From the assignment repository, after loading the course environment:

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

## 11. Repository Structure

Key files from the CSCE 616 Lab 9 environment:

```text
work/
├── tb/
│   ├── htax_tx_driver_c.sv        # Drives TX interface signals
│   ├── htax_tx_monitor_c.sv       # Captures transmitted packets
│   ├── htax_rx_monitor_c.sv       # Captures received packets
│   ├── htax_rx_mon_packet_c.sv    # RX packet transaction class
│   ├── htax_rx_agent_c.sv         # Passive RX agent
│   └── htax_scoreboard_c.sv       # Per-destination comparison queues
├── test/
│   └── multiport_test.sv          # Simultaneous multiport stimulus
└── sim/
    └── run.f                     # Xcelium compilation/run options
```

The complete repository may also contain the DUT, interfaces, TX agent and sequence classes, assertion files, and other tests; their exact filenames depend on the provided lab version.

## 12. Verification Scope and Notes

### What this project checks

- TX-to-RX packet delivery at the **requested destination**.
- Preservation of **VC**, **packet length**, and **payload data**.
- Order-aware matching through **per-destination FIFO queues**.
- Detection of **unexpected RX packets**, **content mismatches**, and **missing packets** at the end of simulation.
- TX/RX interface protocol properties through assertions, when included and enabled.

### Important limitations

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

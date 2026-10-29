# HTAX Crossbar Switch Verification

**SystemVerilog | UVM | SystemVerilog Assertions (SVA) | Packet-Level Scoreboard**

A Universal Verification Methodology (UVM) testbench for a four-port **HyperTransport Advanced X-Bar (HTAX)** crossbar switch. The project verifies that packets injected through a transmit (TX) interface reach the intended receive (RX) interface with the correct **destination port, virtual channel, length, and payload**.

## Table of Contents

- [1. Overview](#1-overview)
- [2. HTAX Architecture](#2-htax-architecture)
- [3. Configurable Parameters](#3-configurable-parameters)
- [4. TX Interface Specification](#4-tx-interface-specification)
- [5. RX Interface Specification](#5-rx-interface-specification)
- [6. UVM Verification Environment](#7-uvm-verification-environment)
- [7. Test Cases and Expected Results](#9-test-cases-and-expected-results)


## 1. Overview

HTAX is a configurable, protocol-agnostic crossbar switch for communication among hardware endpoints. It can be used as an interconnect component in a Network-on-Chip (NoC).

Each HTAX port is bidirectional and exposes two distinct interfaces:

- **TX (transmit):** An external Function Unit(FU) injects a packet into HTAX through its TX interface.
- **RX (receive):** HTAX forwards a packet to an external FU through that FU's RX interface.

A packet sent from FU 0 to FU 3 follows this path:

```text
FU 0 -> Port 0 TX -> HTAX arbitration / switch fabric -> Port 3 RX -> FU 3
```

The transmitter selects a destination **output port** and requests one or more **virtual channels (VCs)**. The crossbar handles contention and coordinates the transfers. The receiver participates in VC-level flow control by issuing receive-side grants.

The HTAX specification describes a scalable design with configurable port count, VC count, bus width, and optional buffering-related capabilities.

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

**Important:** TX and RX refer to the interface directions from the **external FU's perspective**. Both belong to the same bidirectional HTAX port; they are not separate endpoint devices. 

### Example: Port 0 to Port 3

```text
   Sender                             HTAX                          Receiver
+----------+     +-------------+   +-------------------+   +-------------+    +----------+
|   FU 0   | --> |  Port 0 TX  |-->| Switching /       |-->|  Port 3 RX  |--> |   FU 3   |
|          |     |             |   | arbitration       |   |             |    |          |
+----------+     +-------------+   +-------------------+   +-------------+    +----------+

            Destination = Port 3; selected VC and payload remain associated with the packet.
```

## 3. Configurable Parameters

| Parameter | Meaning | Implication |
|---|---|---|
| `PORTS` | Number of bidirectional HTAX ports | Determines the number of TX/RX interfaces and width of `tx_outport_req` |
| `VC` | Number of supported virtual channels | Determines the width of VC request, grant, and SOT vectors |
| `WIDTH` | Width of the payload bus, in bits | Determines the width of `tx_data` and `rx_data` |

The supplied `htax_defines.sv` configures **`PORTS = 4`, `VC = 2`, and `WIDTH = 64`**. Thus, the four TX interfaces and four RX interfaces each have a 64-bit data bus and 2-bit VC request/grant/SOT vectors. These are compile-time configuration macros in this lab, rather than fixed limits of the HTAX specification.

### Virtual channels

A **virtual channel (VC)** is a logical communication channel that allows multiple traffic classes to share the same physical data path while being managed independently.

Virtual channels are important for three main reasons:

-**Quality of Service (QoS):** Different traffic classes can receive different priorities, allowing latency-sensitive packets to be serviced ahead of lower-priority traffic.

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



## 6. UVM Verification Environment

The source-driven testbench uses **four active TX agents**, **four passive RX agents**, and **one shared packet-level scoreboard**. The DUT-facing signal interfaces are instantiated in the SystemVerilog top-level module, while the UVM class hierarchy is assembled under `htax_env`. All data-path monitors sample on **negedges** (the testbench driver drives on posedges).

### 6.1 Top-level DUT and UVM component hierarchy

```text
Packet Transmission Flow
                   ========================

      htax_seqs.sv
            |
            v
   htax_sequencer_c.sv
            |
            v
   htax_tx_driver_c.sv
            |
            v
   htax_tx_interface.sv  <---- htax_tx_monitor_c.sv
            |                         |
            v                         | Expected packets
        +----------+                  |
        | HTAX DUT |                  |
        +----------+                  |
            |                         |
            v                         v
   htax_rx_interface.sv       htax_scoreboard_c.sv
            |                         ^
            v                         | Actual packets
   htax_rx_monitor_c.sv --------------+
```

The actual UVM test class and the `test_lib.svh` contents were **not among the supplied files**. The hierarchy above shows the `tb` environment and components defined in the uploaded sources; the name `tb` is also used by the lab's test-side hierarchy in the existing verification workflow.

### 6.2 Stimulus Generation and Monitoring

- **TX sequence:** `simple_random_seq` produces 15 randomized `htax_packet_c` items. Each item specifies destination port, requested-VC mask, delay, packet length (3–63 beats), and payload.
- **TX driver:** Requests a destination/VC, waits for a grant, and drives `tx_sot`, `tx_data`, `tx_release_gnt`, and `tx_eot`.
- **TX monitor:** Reconstructs outgoing packets from TX signals for expected results.
- **RX monitor:** Captures each packet from `rx_sot` through `rx_eot`, including the final beat, and publishes the received transaction.

### 6.3 Scoreboard and Protocol Checking

The scoreboard uses a **separate FIFO queue for each destination port**:
- **TX Monitoring:** Pushes transmitted packets into exp_q[dest_port] using push_back().
- **RX Checking:** Retrieves the oldest expected packet using pop_front() and compares its VC, length, and payload against the received packet.
- **End-of-Test Checking:** Uses check_phase to detect unmatched packets remaining in any queue.

## 7. Test Cases and Expected Results

| Test | TX traffic | Expected packet count | Success criteria |
|---|---|---:|---|
| `simple_random_test` | Random packets injected on one TX port | 15 TX / 15 RX | All four expected queues empty; zero UVM errors/fatals; TX and RX packets match. |
| `multiport_test` | Random traffic on all four TX ports (15 per TX port in Lab 9) | 60 TX / 60 RX | All four expected queues empty; zero UVM errors/fatals; TX and RX packets match. |
| `mix_sequence_test` | Sequentially runs six directed/randomized sequences: fixed destination, short packets, long packets with short delays, medium packets with fixed VC, port sweep, and random traffic | Depends on the sequence definitions | All generated TX/RX packets match; all four queues empty; zero UVM errors/fatals and no unexpected assertion failures. |




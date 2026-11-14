///////////////////////////////////////////////////////////////////////////
// Texas A&M University
// CSCE 616 Hardware Design Verification
// Created by  : Prof. Quinn and Saumil Gogri
///////////////////////////////////////////////////////////////////////////

	//Declaring analysis TX ports
	`uvm_analysis_imp_decl(_tx0_export)
	`uvm_analysis_imp_decl(_tx1_export)
	`uvm_analysis_imp_decl(_tx2_export)
	`uvm_analysis_imp_decl(_tx3_export)

	//Declaring analysis RX ports
	`uvm_analysis_imp_decl(_rx0_export)
	`uvm_analysis_imp_decl(_rx1_export)
	`uvm_analysis_imp_decl(_rx2_export)
	`uvm_analysis_imp_decl(_rx3_export)

class htax_scoreboard_c extends uvm_scoreboard;

	parameter int PORTS = `PORTS;

	`uvm_component_utils(htax_scoreboard_c)

	uvm_analysis_imp_tx0_export #(htax_tx_mon_packet_c, htax_scoreboard_c) tx0_export;
	uvm_analysis_imp_tx1_export #(htax_tx_mon_packet_c, htax_scoreboard_c) tx1_export;
	uvm_analysis_imp_tx2_export #(htax_tx_mon_packet_c, htax_scoreboard_c) tx2_export;
	uvm_analysis_imp_tx3_export #(htax_tx_mon_packet_c, htax_scoreboard_c) tx3_export;

	uvm_analysis_imp_rx0_export #(htax_rx_mon_packet_c, htax_scoreboard_c) rx0_export;
	uvm_analysis_imp_rx1_export #(htax_rx_mon_packet_c, htax_scoreboard_c) rx1_export;
	uvm_analysis_imp_rx2_export #(htax_rx_mon_packet_c, htax_scoreboard_c) rx2_export;
	uvm_analysis_imp_rx3_export #(htax_rx_mon_packet_c, htax_scoreboard_c) rx3_export;

	//One queue per destination port: the packets sent there and not yet received
	htax_tx_mon_packet_c exp_q [PORTS][$];

	function new (string name, uvm_component parent);
		super.new(name,parent);
		tx0_export=new("tx0_export",this);
		tx1_export=new("tx1_export",this);
		tx2_export=new("tx2_export",this);
		tx3_export=new("tx3_export",this);

		rx0_export=new("rx0_export",this);
		rx1_export=new("rx1_export",this);
		rx2_export=new("rx2_export",this);
		rx3_export=new("rx3_export",this);
	endfunction : new

	//Write methods - TX monitors: every packet sent is expected at its destination
	function void write_tx0_export(htax_tx_mon_packet_c tx_mon_packet);
		push_to_queue(tx_mon_packet);
	endfunction : write_tx0_export

	function void write_tx1_export(htax_tx_mon_packet_c tx_mon_packet);
		push_to_queue(tx_mon_packet);
	endfunction : write_tx1_export

	function void write_tx2_export(htax_tx_mon_packet_c tx_mon_packet);
		push_to_queue(tx_mon_packet);
	endfunction : write_tx2_export

	function void write_tx3_export(htax_tx_mon_packet_c tx_mon_packet);
		push_to_queue(tx_mon_packet);
	endfunction : write_tx3_export

	//Write methods - RX monitors: every packet received is compared with the oldest one expected there
	function void write_rx0_export(htax_rx_mon_packet_c rx_mon_packet);
		compare_pkt(0, rx_mon_packet);
	endfunction : write_rx0_export

	function void write_rx1_export(htax_rx_mon_packet_c rx_mon_packet);
		compare_pkt(1, rx_mon_packet);
	endfunction : write_rx1_export

	function void write_rx2_export(htax_rx_mon_packet_c rx_mon_packet);
		compare_pkt(2, rx_mon_packet);
	endfunction : write_rx2_export

	function void write_rx3_export(htax_rx_mon_packet_c rx_mon_packet);
		compare_pkt(3, rx_mon_packet);
	endfunction : write_rx3_export

	//TO DO (Task 2) : Add a TX monitor packet to the back of exp_q[mon_pkt.dest_port].
	//                 A dest_port outside 0..PORTS-1 is a uvm_error, not a crash.
	function void push_to_queue(htax_tx_mon_packet_c mon_pkt);
		if (mon_pkt.dest_port < 0 || mon_pkt.dest_port >= PORTS) begin
			`uvm_error("SCOREBOARD",
				$sformatf("Invalid destination port: %0d", mon_pkt.dest_port))
			return;
		end
		exp_q[mon_pkt.dest_port].push_back(mon_pkt);
	endfunction : push_to_queue

	//TO DO (Task 3) : Compare a packet received on port with the oldest packet sent to that port.
	//  1. If exp_q[port] is empty, the packet was never sent: report a uvm_error and return.
	//  2. Otherwise take the packet at the front of exp_q[port] off the queue.
	//  3. Compare vc, length and data. If any differs, report one uvm_error that shows both packets.
	htax_tx_mon_packet_c pkt;

	function void compare_pkt(int port, htax_rx_mon_packet_c rx_mon_packet);
		htax_tx_mon_packet_c pkt;
		if (port < 0 || port >= PORTS) begin
			`uvm_error("SCOREBOARD",
				$sformatf("Invalid RX port: %0d", port))
			return;
		end
		if (exp_q[port].size() == 0) begin //Rx received an unexpected packet.
			`uvm_error("SCOREBOARD",
				$sformatf("Port %0d queue is empty. Unexpected RX packet: %s",
						port, rx_mon_packet.convert2string()))
			return;
		end
		pkt = exp_q[port].pop_front();
		if (pkt.vc !== rx_mon_packet.vc || pkt.length !== rx_mon_packet.length || pkt.data !== rx_mon_packet.data) begin
			`uvm_error("SCOREBOARD",
				$sformatf("Packet mismatch on port %0d\nExpected TX: %s\nActual RX: %s",
						port,
						pkt.convert2string(),
						rx_mon_packet.convert2string()))
		end
		else begin
			`uvm_info("SCOREBOARD",
				$sformatf("Packet matched on port %0d",
						port),
				UVM_LOW)
		end
	endfunction : compare_pkt

	//A packet that was sent and never received leaves its queue non-empty
	function void check_phase(uvm_phase phase);
		`uvm_info("SCOREBOARD", "End of Simulation Checking", UVM_NONE)
		for (int p = 0; p < PORTS; p++)
			if (exp_q[p].size() == 0)
				`uvm_info("SCOREBOARD", $sformatf("Port %0d Queue is empty", p), UVM_NONE)
			else
				`uvm_error("SCOREBOARD", $sformatf("Port %0d Queue holds %0d packet(s) that never arrived", p, exp_q[p].size()))
	endfunction : check_phase

endclass : htax_scoreboard_c

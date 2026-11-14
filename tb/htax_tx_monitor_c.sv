///////////////////////////////////////////////////////////////////////////
// Texas A&M University
// CSCE 616 Hardware Design Verification
// Created by  : Prof. Quinn and Saumil Gogri
///////////////////////////////////////////////////////////////////////////

class htax_tx_monitor_c extends uvm_monitor;

	parameter int PORTS = `PORTS;
	parameter int VC    = `VC;

	//Factory Registration
	`uvm_component_utils(htax_tx_monitor_c)

	//Analysis port to communicate with Scoreboard
	uvm_analysis_port #(htax_tx_mon_packet_c) tx_collect_port;

	virtual interface htax_tx_interface htax_tx_intf;
	htax_tx_mon_packet_c tx_mon_packet;
	bit [`WIDTH-1:0] beats [$];

	//Packet coverage: sampled once per packet, when the packet is complete
	covergroup cover_htax_packet;
		option.per_instance = 1;
		option.name = "cover_htax_packet";

		//Destination port
		DEST_PORT : coverpoint tx_mon_packet.dest_port {
			bins dest_port[] = {[0:3]};
		}

		//TO DO (Task 1) : VC, LENGTH, X_DEST_PORT__VC, X_DEST_PORT__LENGTH, X_VC__LENGTH
		VC : coverpoint tx_mon_packet.vc{
			bins vc[] = {[0:1]};
			illegal_bins invalid_vc = default;
		}
		LENGTH : coverpoint tx_mon_packet.length{
			bins length[16] = {[3:63]};
			illegal_bins ill_len = {[$:2]};
		}
		X_DEST_PORT__VC : cross DEST_PORT, VC;
		X_DEST_PORT__LENGTH : cross DEST_PORT, LENGTH;
		X_VC__LENGTH : cross VC, LENGTH;
	endgroup

	//Interface coverage: sampled once per packet, at the grant
	covergroup cover_htax_tx_intf;
		option.per_instance = 1;
		option.name = "cover_htax_tx_intf";

		//TO DO (Task 2) : OUTPORT_REQ, TX_VC_REQ, TX_VC_GNT
		OUTPORT_REQ : coverpoint htax_tx_intf.tx_outport_req{
			bins tx_outport_req[] = {4'b0001, 4'b0010, 4'b0100, 4'b1000};
			illegal_bins ill_outport_req = default;
		}
		TX_VC_REQ : coverpoint htax_tx_intf.tx_vc_req{
			bins tx_vc_req[] = {2'b01, 2'b10, 2'b11};
			illegal_bins ill_vc_req = {2'b00};
		}
		TX_VC_GNT : coverpoint htax_tx_intf.tx_vc_gnt{
			bins tx_vc_gnt[] = {2'b01, 2'b10, 2'b11};
		}
	endgroup

	//constructor
	function new (string name, uvm_component parent);
		super.new(name,parent);
		tx_collect_port = new ("tx_collect_port", this);
		cover_htax_packet  = new();
		cover_htax_tx_intf = new();
	endfunction : new

	//UVM build phase
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if(!uvm_config_db#(virtual htax_tx_interface)::get(this,"","tx_vif",htax_tx_intf))
			`uvm_fatal("NO_TX_VIF",{"Virtual Interface needs to be set for ", get_full_name(),".tx_vif"})
	endfunction : build_phase

	task run_phase(uvm_phase phase);
		forever begin
			tx_mon_packet = htax_tx_mon_packet_c::type_id::create("tx_mon_packet");

			//The driver changes the TX signals on the rising clock edge, so sample them on the falling edge.
			@(negedge htax_tx_intf.clk iff |htax_tx_intf.tx_vc_gnt);   //a packet has been granted
			cover_htax_tx_intf.sample();
			foreach (htax_tx_intf.tx_outport_req[i])
				if (htax_tx_intf.tx_outport_req[i]) tx_mon_packet.dest_port = i;

			@(negedge htax_tx_intf.clk iff |htax_tx_intf.tx_sot);      //first beat
			foreach (htax_tx_intf.tx_sot[i])
				if (htax_tx_intf.tx_sot[i]) tx_mon_packet.vc = i;

			beats = {};
			forever begin
				beats.push_back(htax_tx_intf.tx_data);
				if (htax_tx_intf.tx_eot) break;
				@(negedge htax_tx_intf.clk);
			end
			tx_mon_packet.data   = beats;
			tx_mon_packet.length = beats.size();

			`uvm_info("TX_MON", tx_mon_packet.convert2string(), UVM_LOW)
			tx_collect_port.write(tx_mon_packet);
			cover_htax_packet.sample();
		end
	endtask : run_phase

endclass : htax_tx_monitor_c



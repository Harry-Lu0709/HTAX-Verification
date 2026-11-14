///////////////////////////////////////////////////////////////////////////
// Texas A&M University
// CSCE 616 Hardware Design Verification
// Created by  : Prof. Quinn and Saumil Gogri
///////////////////////////////////////////////////////////////////////////

class htax_rx_monitor_c extends uvm_monitor;

	`uvm_component_utils(htax_rx_monitor_c)

	//Analysis port to communicate with Scoreboard
	uvm_analysis_port #(htax_rx_mon_packet_c) rx_collect_port;

	virtual interface htax_rx_interface htax_rx_intf;
	htax_rx_mon_packet_c rx_mon_packet;
	int port;                   //RX port this monitor watches, set by the environment
	bit [`WIDTH-1:0] beats [$];

	//TO DO (Task 3) : Declare covergroup cover_htax_rx_packet: RX_VC, RX_LENGTH, X_RX_VC__LENGTH
	covergroup cover_htax_rx_packet;
		option.per_instance = 1;
		option.name = "cover_htax_rx_packet";

		RX_VC : coverpoint rx_mon_packet.vc{
			bins vc[] = {0, 1};
			illegal_bins ill_vc = default;
		}
		RX_LENGTH : coverpoint rx_mon_packet.length{
			bins short_len = {[3:15]};
			bins mid_len = {[16:47]};
			bins long_len = {[48:63]};
			illegal_bins ill_len = {[$:2]};
		}
		X_RX_VC__LENGTH : cross RX_VC, RX_LENGTH;
	endgroup

	function new (string name, uvm_component parent);
		super.new(name, parent);
		rx_collect_port = new ("rx_collect_port", this);
		//TO DO (Task 3) : Create the covergroup
		cover_htax_rx_packet = new();
	endfunction : new

	function void build_phase (uvm_phase phase);
		super.build_phase(phase);
		if(!uvm_config_db#(virtual htax_rx_interface)::get(this,"","rx_vif",htax_rx_intf))
			`uvm_fatal("RX_VIF",{"Virtual Interface needs to be set for ",get_full_name(),".rx_vif"})
	endfunction : build_phase

	task run_phase(uvm_phase phase);
		forever begin
			rx_mon_packet = htax_rx_mon_packet_c::type_id::create("rx_mon_packet");
			rx_mon_packet.port = port;

			//Sample on the falling edge, half a cycle away from the edge the signals change on
			@(negedge htax_rx_intf.clk iff |htax_rx_intf.rx_sot);      //first beat
			foreach (htax_rx_intf.rx_sot[i])
				if (htax_rx_intf.rx_sot[i]) rx_mon_packet.vc = i;

			beats = {};
			forever begin
				beats.push_back(htax_rx_intf.rx_data);
				if (htax_rx_intf.rx_eot) break;
				@(negedge htax_rx_intf.clk);
			end
			rx_mon_packet.data   = beats;
			rx_mon_packet.length = beats.size();

			`uvm_info("RX_MON", rx_mon_packet.convert2string(), UVM_LOW)
			rx_collect_port.write(rx_mon_packet);
			//TO DO (Task 3) : Sample the covergroup
			cover_htax_rx_packet.sample();
		end
	endtask : run_phase

endclass : htax_rx_monitor_c

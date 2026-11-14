///////////////////////////////////////////////////////////////////////////
// Texas A&M University
// CSCE 616 Hardware Design Verification
// Created by  : Prof. Quinn and Saumil Gogri
///////////////////////////////////////////////////////////////////////////

class htax_tx_driver_c extends uvm_driver #(htax_packet_c);

	parameter int PORTS = `PORTS;
	parameter int VC    = `VC;
	parameter int WIDTH = `WIDTH;

	`uvm_component_utils(htax_tx_driver_c)

	virtual interface htax_tx_interface htax_tx_intf;

	//Constructor
	function new (string name, uvm_component parent);
		super.new(name,parent);
	endfunction : new

	//UVM build phase
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if(!uvm_config_db#(virtual htax_tx_interface)::get(this,"","tx_vif",htax_tx_intf))
			`uvm_fatal("NO_TX_VIF",{"Virtual Interface needs to be set for ", get_full_name(),".tx_vif"})
	endfunction : build_phase

	//UVM run_phase
	task run_phase(uvm_phase phase);
		rst_dut_and_signal();               //Reset the interface signals
		forever begin                       //Till end of test
			seq_item_port.get_next_item(req); //Get next pkt from sequencer
			drive_thru_dut(req);              //Drive pkt to DUT via interface
			seq_item_port.item_done();        //Sends ACK to sequencer
		end
	endtask : run_phase

	task rst_dut_and_signal();
		@(negedge htax_tx_intf.rst_n);
		`uvm_info("TOP", "Resetting the DUT synchronously", UVM_NONE)
		@(posedge htax_tx_intf.clk)
		htax_tx_intf.tx_outport_req  = 'b0;
		htax_tx_intf.tx_vc_req       = 'b0;
		htax_tx_intf.tx_sot          = 'b0;
		htax_tx_intf.tx_release_gnt  = 'b0;
		htax_tx_intf.tx_eot          = 'b0;
	endtask : rst_dut_and_signal

	extern protected task drive_thru_dut(htax_packet_c pkt);
endclass : htax_tx_driver_c

//TO DO (Task 1) : COMPLETE THE DRIVER CODE BELOW
task htax_tx_driver_c::drive_thru_dut(htax_packet_c pkt);

	int ch;   //The channel this packet is sent on: the index of the bit you set in tx_sot
	logic [VC-1:0] temp;
	int q[$];
	int index;

	`uvm_info (get_type_name(), $sformatf("Input Data Packet to DUT : \n%s", pkt.sprint()),UVM_HIGH)

	//Wait for pkt.delay clock cycles
	repeat (pkt.delay) @(posedge htax_tx_intf.clk);

	//On next clk-posedge
	//TO DO : Set htax_tx_intf.tx_outport_req in one-hot fashion from pkt.dest_port
	//TO DO : Assign htax_tx_intf.tx_vc_req from pkt.vc
	@(posedge htax_tx_intf.clk)

	htax_tx_intf.tx_outport_req <= 1 << pkt.dest_port;
	htax_tx_intf.tx_vc_req <= pkt.vc;

	//TO DO : Wait till htax_tx_intf.tx_vc_gnt is received
	//TO DO : Set ch, at random, to a channel that pkt.vc requested and tx_vc_gnt granted
	wait (|(pkt.vc & htax_tx_intf.tx_vc_gnt));

	temp = (pkt.vc & htax_tx_intf.tx_vc_gnt);
	
	for(int i = 0; i < VC; i++)
		if(temp[i])
			q.push_back(i);
	index = $urandom_range(q.size()-1, 0);
	ch = q[index];

	//On next clk-posedge
	//TO DO : Set bit ch of htax_tx_intf.tx_sot to 1 (and no other bit)
	//TO DO : Drive pkt.data[0] on htax_tx_intf.tx_data
	//TO DO : Reset htax_tx_intf.tx_outport_req and htax_tx_intf.tx_vc_req (to zero)
	@(posedge htax_tx_intf.clk)

	htax_tx_intf.tx_sot <= 1<<ch;
	htax_tx_intf.tx_data <= pkt.data[0];
	htax_tx_intf.tx_outport_req <= 0;
	htax_tx_intf.tx_vc_req <= 0;

	//TO DO : On consecutive clk-posedges drive each of the packet's pkt.data on htax_tx_intf.tx_data
	//TO DO : Assign htax_tx_intf.tx_sot to zero after first cycle
	//TO DO : Assert htax_tx_intf.tx_release_gnt for one clock cycle when driving second last data packet
	//TO DO : Assert htax_tx_intf.tx_eot for one clock cycle when driving last data packet
	for(int i=1; i < pkt.length; i++) begin  //TO DO : Replace XXX and YYY with appropriate values for a packet
		@(posedge htax_tx_intf.clk)

		htax_tx_intf.tx_data <= pkt.data[i];	
		htax_tx_intf.tx_sot <= '0;

		htax_tx_intf.tx_release_gnt <= 1'b0;
		htax_tx_intf.tx_eot <= 1'b0;
		if(i == pkt.length-2)	
			htax_tx_intf.tx_release_gnt <= 1'b1;
		if(i == pkt.length-1)	
			htax_tx_intf.tx_eot <= 1'b1;
	end

	//On next clk-posedge
	//TO DO : Assign htax_tx_intf.tx_data to X and htax_tx_intf.tx_eot to zero
	@(posedge htax_tx_intf.clk)

	htax_tx_intf.tx_data <= 'x;
	htax_tx_intf.tx_eot <= 1'b0;

	//One line per packet, compared with the monitor's TX_MON line in Task 4
	`uvm_info("TX_DRV", htax_tx_mon_packet_c::summary(pkt.dest_port, ch, pkt.length, pkt.data), UVM_LOW)
endtask : drive_thru_dut

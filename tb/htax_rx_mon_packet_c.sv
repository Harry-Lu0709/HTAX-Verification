///////////////////////////////////////////////////////////////////////////
// Texas A&M University
// CSCE 616 Hardware Design Verification
// Created by  : Prof. Quinn and Saumil Gogri
///////////////////////////////////////////////////////////////////////////

class htax_rx_mon_packet_c extends uvm_sequence_item;

	parameter int PORTS = `PORTS;
	parameter int VC    = `VC;
	parameter int WIDTH = `WIDTH;

	int             port;       //RX port the packet arrived on
	int             vc;         //Channel it arrived on: the index of the bit set in rx_sot
	int             length;     //Number of data beats
	bit [WIDTH-1:0] data [];    //One entry per beat

	`uvm_object_utils_begin(htax_rx_mon_packet_c)
		`uvm_field_int(port,UVM_ALL_ON)
		`uvm_field_int(vc,UVM_ALL_ON)
		`uvm_field_int(length,UVM_ALL_ON|UVM_DEC)
		`uvm_field_array_int(data,UVM_ALL_ON)
	`uvm_object_utils_end

	function new (string name = "htax_rx_mon_packet_c");
		super.new(name);
	endfunction : new

	//One line per packet, in the same format as the TX monitor's TX_MON line
	function string convert2string();
		return htax_tx_mon_packet_c::summary(port, vc, length, data);
	endfunction

endclass : htax_rx_mon_packet_c

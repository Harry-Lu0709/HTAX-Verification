///////////////////////////////////////////////////////////////////////////
// Texas A&M University
// CSCE 616 Hardware Design Verification
// File name   : htax_packet_c.sv
// Created by  : Prof. Quinn and Saumil Gogri
///////////////////////////////////////////////////////////////////////////


class htax_packet_c extends uvm_sequence_item;

	parameter int PORTS = `PORTS;
	parameter int VC    = `VC;
	parameter int WIDTH = `WIDTH;

	rand int             delay;      //Delay of the packet
	rand int             dest_port;  //Destination port of packet
	rand bit [VC-1:0]    vc;         //Virtual channels requested. More than one bit may be set
	rand int             length;     //Length of data in beats
	rand bit [WIDTH-1:0] data [];    //Data - Each data packet is WIDTH-bit wide

	// UVM macros for built-in automation
	`uvm_object_utils_begin(htax_packet_c)
		`uvm_field_int(delay,UVM_ALL_ON)
		`uvm_field_int(dest_port,UVM_ALL_ON)
		`uvm_field_int(vc,UVM_ALL_ON)
		`uvm_field_int(length,UVM_ALL_ON)
		`uvm_field_array_int(data,UVM_ALL_ON)
	`uvm_object_utils_end

	//constructor
	function new (string name="htax_packet_c");
		super.new(name);
	endfunction

	constraint delay_c { delay inside {[1:20]}; }

	constraint dest_port_c { dest_port inside {[0:PORTS-1]}; }

	// A request for no channel at all cannot be sent anywhere
	constraint vc_c { vc != 0; }

	constraint length_c {
		length dist {[3:15]:/50, [16:47]:/40, [48:63]:/10};
		data.size() == length;
	}

	// Short packets use the minimal-latency feature, which requires a
	// one-hot channel request (HTAX spec 4.2, tx_sot)
	constraint short_pkt_c { (length <= 15) -> ($countones(vc) == 1); }

endclass : htax_packet_c





///////////////////////////////////////////////////////////////////////////
// Texas A&M University
// CSCE 616 Hardware Design Verification
// Created by  : Prof. Quinn and Saumil Gogri
///////////////////////////////////////////////////////////////////////////

class htax_tx_mon_packet_c extends uvm_sequence_item;

	parameter int PORTS = `PORTS;
	parameter int VC    = `VC;
	parameter int WIDTH = `WIDTH;

	int             dest_port;  //Destination port number, from tx_outport_req
	int             vc;         //Channel the packet was sent on: the index of the bit set in tx_sot
	int             length;     //Number of data beats
	bit [WIDTH-1:0] data [];    //One entry per beat

	`uvm_object_utils_begin(htax_tx_mon_packet_c)
		`uvm_field_int(dest_port,UVM_ALL_ON)
		`uvm_field_int(vc,UVM_ALL_ON)
		`uvm_field_int(length,UVM_ALL_ON|UVM_DEC)
		`uvm_field_array_int(data,UVM_ALL_ON)
	`uvm_object_utils_end

	function new (string name = "htax_tx_mon_packet_c");
		super.new(name);
	endfunction : new

	//One line per packet. The driver prints its TX_DRV line with summary() too,
	//so the two lines are identical when driver and monitor agree.
	function string convert2string();
		return summary(dest_port, vc, length, data);
	endfunction

	static function string summary(int port, int vc, int length, bit [WIDTH-1:0] data []);
		string s = $sformatf("port=%0d vc=%0d length=%0d data=", port, vc, length);
		foreach (data[i])
			s = {s, $sformatf("%h", data[i]), (i < data.size()-1) ? "_" : ""};
		return s;
	endfunction

endclass : htax_tx_mon_packet_c

///////////////////////////////////////////////////////////////////////////
// Texas A&M University
// CSCE 616 Hardware Design Verification
// Created by  : Prof. Quinn and Saumil Gogri
///////////////////////////////////////////////////////////////////////////

//Base sequence 
class htax_base_seq extends uvm_sequence #(htax_packet_c); //HTAX packet class is passed as parameter
//htax_base_seq is a UVM sequence, it produce htax_packet_c
  parameter int PORTS = `PORTS;
  parameter int VC    = `VC;
  parameter int WIDTH = `WIDTH;

	//Factory Registration
	`uvm_object_utils(htax_base_seq)

	//Constructor
	function new ( string name = "htax_base_seq");
		super.new(name);
	endfunction : new

endclass : htax_base_seq

//Sequence 1
//Fix Destination Port Sequence extends from base sequence
class fix_dest_port_seq extends htax_base_seq;

	//Factory Registration
	`uvm_object_utils(fix_dest_port_seq)

	//Constructor
	function new ( string name = "fix_dest_port_seq");
    super.new(name);
  endfunction : new

	//Body task -- 
	virtual task body();
		int i;
		i=$urandom_range(0,PORTS-1);
		`uvm_info(get_type_name(),"Executing fix destination port sequence with 5 transactions", UVM_NONE)
		//Generate a sequence with 5 packets
		repeat(5) begin //req is a handle of htax_packet_c
			`uvm_do_with (req, {req.dest_port==i;}) //fix dest_port 
		end
	endtask

endclass : fix_dest_port_seq


//TO DO (Task 1) - short_packet_seq extends from base sequence
class short_packet_seq extends htax_base_seq;

	//Factory Registration
	`uvm_object_utils(short_packet_seq)

	//Constructor
	function new ( string name = "short_packet_seq");
    super.new(name);
  endfunction : new

	//Body task -- 
	virtual task body();
		`uvm_info(get_type_name(),"Executing short packet sequence with 5 transactions", UVM_NONE)
		//Generate a sequence with 5 packets
		repeat(5) begin
			`uvm_do_with(req, {req.length inside {[3:15]};}) 
		end
	endtask

endclass : short_packet_seq


//TO DO (Task 1) - long_packet_short_delay_seq extends from base sequence
class long_packet_short_delay_seq extends htax_base_seq;

	//Factory Registration
	`uvm_object_utils(long_packet_short_delay_seq)

	//Constructor
	function new ( string name = "long_packet_short_delay_seq");
    super.new(name);
  endfunction : new

	//Body task -- 
	virtual task body();
		`uvm_info(get_type_name(),"Executing long packet short delay sequence with 5 transactions", UVM_NONE)
		//Generate a sequence with 5 packets
		repeat(5) begin
			`uvm_do_with(req, {req.length inside {[48:63]}; req.delay inside {[1:3]};}) 
		end
	endtask

endclass : long_packet_short_delay_seq


//TO DO (Task 1) - med_packet_fix_vc_seq extends from base sequence
class med_packet_fix_vc_seq extends htax_base_seq;

	//Factory Registration
	`uvm_object_utils(med_packet_fix_vc_seq)

	//Constructor
	function new ( string name = "med_packet_fix_vc_seq");
    super.new(name);
  endfunction : new

	//Body task -- 
	virtual task body();		
		//Generate a sequence with 5 packets
		bit [VC-1:0] i;
		int vc_idx;
		vc_idx = $urandom_range(0, VC-1);
		i = '0;
        i[vc_idx] = 1'b1;

		`uvm_info(get_type_name(),"Executing medium packet fix vc sequence with 5 transactions", UVM_NONE)
		repeat(5) begin
			`uvm_do_with(req, {
				req.length inside {[16:47]}; 
				req.vc == i;
			 }) 
		end
	endtask

endclass : med_packet_fix_vc_seq


//TO DO (Task 1) - port_sweep_seq extends from base sequence
class port_sweep_seq extends htax_base_seq;

	//Factory Registration
	`uvm_object_utils(port_sweep_seq)

	//Constructor
	function new ( string name = "port_sweep_seq");
    super.new(name);
  endfunction : new

	//Body task -- 
	virtual task body();		
		//Generate a sequence with 5 packets
		int Port_array [0:PORTS-1];
		int index = 0;
		for(int i=0; i<PORTS; i++)
			Port_array[i] = i;
		Port_array.shuffle();
		`uvm_info(get_type_name(),"Executing port sweep sequence with PORTS transactions", UVM_NONE)
		/*repeat(PORTS) begin
			`uvm_do_with(req, {
				req.dest_port == Port_array[index];
			 }) 
			 index++;
		end*/
		for (int i = 0; i < PORTS; i++) begin
			`uvm_do_with(req, {
				req.dest_port == Port_array[i];
			})
		end
	endtask

endclass : port_sweep_seq


//TO DO (Task 1) - random_seq extends from base sequence
class random_seq extends htax_base_seq;

	//Factory Registration
	`uvm_object_utils(random_seq)

	//Constructor
	function new ( string name = "random_seq");
    super.new(name);
  endfunction : new

	//Body task -- 
	virtual task body();		
		//Generate a sequence with 5 packets
		`uvm_info(get_type_name(),"Executing random sequence with 5 transactions", UVM_NONE)
		repeat(5) begin
			`uvm_do(req) 
		end
	endtask

endclass : random_seq

//Closes the coverage of the TX monitor on port 1, in at most 100 packets
class coverage_seq extends htax_base_seq;
	/*int lengths[16] = '{
		3, 7, 11, 15,
		19, 23, 27, 31,
		35, 39, 43, 47,
		51, 55, 59, 63
	};*/
	int lengths[21] = '{
		3, 6, 9, 12,
		15, 18, 21, 24,
		27, 30, 33, 36,
		39, 42, 45, 48,
		51, 54, 57, 60,
		63
	};
	`uvm_object_utils(coverage_seq)

	function new (string name = "coverage_seq");
		super.new(name);
	endfunction : new

	virtual task body();
		bit [`VC-1:0] target_vc;
		int idx;
		//TO DO (Task 4) : Send at most 100 packets that close the TX monitor coverage on port 1
		`uvm_info(get_type_name(),"Executing coverage sequence", UVM_NONE)
	
		for(int len = 0; len < 21; len++)
		begin
			for(int port = 0; port < 4; port++) begin
				idx = len % 4;
				if(lengths[len] <= 15) begin //see htax_packet_c.sv -> constraint short_pkt_c
					case (port)
						0: target_vc = 2'b01;
						1: target_vc = 2'b01;
						2: target_vc = 2'b10;
						3: target_vc = 2'b10;
					endcase					
				end
				else begin
					if(idx == 0) begin
						case (port)
							0: target_vc = 2'b01;
							1: target_vc = 2'b10;
							2: target_vc = 2'b11;
							3: target_vc = 2'b11;
						endcase	
					end	
					else if(idx == 1) begin
						case (port)
							0: target_vc = 2'b11;
							1: target_vc = 2'b01;
							2: target_vc = 2'b10;
							3: target_vc = 2'b11;
						endcase	
					end
					else if(idx == 2) begin
						case (port)
							0: target_vc = 2'b11;
							1: target_vc = 2'b11;
							2: target_vc = 2'b01;
							3: target_vc = 2'b10;
						endcase	
					end
					else if(idx == 3) begin
						case (port)
							0: target_vc = 2'b10;
							1: target_vc = 2'b11;
							2: target_vc = 2'b11;
							3: target_vc = 2'b01;
						endcase	
					end
				end
				`uvm_do_with(req, {req.dest_port == port; req.length == lengths[len]; req.vc == target_vc;})
				
			end
		end

	endtask

endclass : coverage_seq
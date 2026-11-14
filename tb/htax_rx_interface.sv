///////////////////////////////////////////////////////////////////////////
// Texas A&M University
// CSCE 616 Hardware Design Verification
// Created by  : Prof. Quinn and Saumil Gogri
///////////////////////////////////////////////////////////////////////////

interface htax_rx_interface(input clk, rst_n);
	
	import uvm_pkg::*;
	`include "uvm_macros.svh"

	parameter int PORTS = `PORTS;
	parameter int VC		= `VC;
	parameter int WIDTH	=	`WIDTH;

	logic [VC-1:0] 	rx_vc_req;
	logic [VC-1:0] 	rx_vc_gnt = '0;   // starts at 0, not X
	logic [WIDTH-1:0] rx_data;
	logic [VC-1:0] 	rx_sot;
	logic 					rx_eot;
	logic 					tran_on=0;

	always @(|rx_vc_req) begin
		wait (tran_on==0);
			@(posedge clk);
		rx_vc_gnt=rx_vc_req;
	end

	always @(posedge (|rx_sot))
		tran_on=1;

	always @(negedge rx_eot)
		tran_on=0;

	//TO DO (Task 2) : ASSERTIONS

   // ----------------------------------------------
   // rx_sot is one-hot and lasts one clock cycle
   // ----------------------------------------------
	property rx_sot_one_hot;
		@(posedge clk) disable iff(!rst_n)
		(|rx_sot) |-> $onehot(rx_sot) ##1 (rx_sot == '0);
	endproperty

	assert_rx_sot_one_hot : assert property(rx_sot_one_hot)
	else
		$error("HTAX_RX_INF ERROR : rx_sot is NOT one-hot and lasts one clock cycle");


   // ----------------------------------------------
   // rx_eot lasts one clock cycle
   // ----------------------------------------------
	property rx_eot_one_cycle;
		@(posedge clk) disable iff(!rst_n)
		rx_eot |=> !rx_eot;
	endproperty

	assert_rx_eot_one_cycle : assert property(rx_eot_one_cycle)
	else
		$error("HTAX_RX_INF ERROR : rx_eot is NOT one clock cycle");


   // ----------------------------------------------
   // rx_vc_gnt is not withdrawn before the transaction starts(see figure 9.)
   // ----------------------------------------------
	genvar i;
	generate
	for (i = 0; i < VC; i++) begin : gen_rx_vc_gnt_assert

		property rx_vc_gnt_asserted_before_transaction;
			@(posedge clk) disable iff(!rst_n)
			($rose(rx_vc_gnt[i]))
			|-> (rx_vc_gnt[i] until_with rx_vc_req[i]);
		endproperty

		assert_rx_vc_gnt_asserted_before_transaction :
			assert property(rx_vc_gnt_asserted_before_transaction)
			else
				$error("HTAX_RX_INF ERROR : rx_vc_gnt[%0d] withdrawn before transaction starts", i);

	end
	endgenerate


endinterface : htax_rx_interface







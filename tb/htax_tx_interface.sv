///////////////////////////////////////////////////////////////////////////
// Texas A&M University
// CSCE 616 Hardware Design Verification
// Created by  : Prof. Quinn and Saumil Gogri
///////////////////////////////////////////////////////////////////////////

interface htax_tx_interface (input clk, rst_n);

  import uvm_pkg::*;
  `include "uvm_macros.svh"

	parameter int PORTS = `PORTS;
	parameter int VC = `VC;
	parameter int WIDTH = `WIDTH;
	
	logic [PORTS-1:0] tx_outport_req;
	logic [VC-1:0] 		tx_vc_req;
	logic [VC-1:0] 		tx_vc_gnt;
	logic [WIDTH-1:0]	tx_data;
	logic [VC-1:0]		tx_sot;
	logic							tx_eot;
	logic 						tx_release_gnt;

//TO DO (Task 1) : ASSERTIONS

   // --------------------------- 
   // tx_outport_req is one-hot 
   // --------------------------- 
   property tx_outport_req_one_hot;
      @(posedge clk) disable iff(!rst_n)
      (|tx_outport_req) |-> $onehot(tx_outport_req);
   endproperty

   assert_tx_outport_req_one_hot : assert property(tx_outport_req_one_hot)
   else
      $error("HTAX_TX_INF ERROR : tx_outport request is not one hot encoded");

   // ----------------------------------- 
   // no tx_outport_req without tx_vc_req
   // ----------------------------------- 
   property no_tx_outport_req_without_tx_vc_req;
      @(posedge clk) disable iff(!rst_n)
      (|tx_outport_req) |-> (|tx_vc_req);
   endproperty
   assert_no_tx_outport_req_without_tx_vc_req : assert property(no_tx_outport_req_without_tx_vc_req)
   else
      $error("HTAX_TX_INF ERROR : tx_outport_req without tx_vc_req");


   // ----------------------------------- 
   // no tx_vc_req without tx_outport_req
   // ----------------------------------- 
   property no_tx_vc_req_without_tx_outport_req;
      @(posedge clk) disable iff(!rst_n)
      (|tx_vc_req) |-> (|tx_outport_req);
   endproperty
   assert_no_tx_vc_req_without_tx_outport_req : assert property(no_tx_vc_req_without_tx_outport_req)
   else
      $error("HTAX_TX_INF ERROR : tx_vc_req without tx_outport_req");
   /*--------------------------------------------------------------------------------------------------------
      Since tx_vc_req and tx_outport_req has to be asserted/deasserted at the same time.
      We need a bidirectional tx_vc_req/tx_outport_req.
      If only no tx_outport_req without tx_vc_req, if outport_req = 0/vc_req = 1 it will not catch the error.
   */


   // ----------------------------------- 
   // tx_vc_gnt is subset of vc_request
   // ----------------------------------- 
   property tx_vc_gnt_subset_vc_request;
      @(posedge clk) disable iff(!rst_n)
      ((tx_vc_gnt & ~tx_vc_req) == '0);
   endproperty
   assert_tx_vc_gnt_subset_vc_request : assert property(tx_vc_gnt_subset_vc_request)
   else
      $error("HTAX_TX_INF ERROR : tx_vc_gnt is not a subset of vc_request");


   // ------------------------------------ 
   // no tx_sot without previous tx_vc_gnt 
   // ------------------------------------ 
   logic grant_seen;
   always_ff@ (posedge clk or negedge rst_n) begin
      if(!rst_n)
         grant_seen <= 1'b0;
      else if(|$sampled(tx_vc_gnt))
         grant_seen <= 1'b1;
      else if($sampled(tx_eot))
         grant_seen <= 1'b0;
   end
   property no_tx_sot_without_previous_tx_vc_gnt;
      @(posedge clk) disable iff(!rst_n)
      |tx_sot |-> grant_seen;
   endproperty
   assert_no_tx_sot_without_previous_tx_vc_gnt : assert property(no_tx_sot_without_previous_tx_vc_gnt)
   else
      $error("HTAX_TX_INF ERROR : tx_sot without previous tx_vc_gnt");


   // ------------------------------------ 
   // no tx_eot without previous tx_vc_gnt 
   // ------------------------------------ 
   property no_tx_eot_without_previous_tx_vc_gnt;
      @(posedge clk) disable iff(!rst_n)
      tx_eot |-> grant_seen;
   endproperty
   assert_no_tx_eot_without_previous_tx_vc_gnt : assert property(no_tx_eot_without_previous_tx_vc_gnt)
   else
      $error("HTAX_TX_INF ERROR : tx_eot without previous tx_vc_gnt");


   // ------------------------------------------- 
   // tx_eot is asserted for a single clock cycle 
   // ------------------------------------------- 
   property tx_eot_single_cycle;
      @(posedge clk) disable iff(!rst_n)
      tx_eot |=> !tx_eot;
   endproperty
   assert_tx_eot_single_cycle : assert property(tx_eot_single_cycle)
   else
      $error("HTAX_TX_INF ERROR : tx_eot is NOT asserted for a single clock cycle");


   // ------------------------------------------------------------- 
   // tx_release_gnt for pkt(t) one clock cycle or same clock cycle with tx_eot of pkt(t)
   // ------------------------------------------------------------- 
   property tx_release_gnt_one_same_cycle_tx_eot;
      @(posedge clk) disable iff(!rst_n)
      tx_eot |-> (tx_release_gnt || $past(tx_release_gnt));  //overlap means there is only one data
   endproperty
   assert_tx_release_gnt_one_same_cycle_tx_eot : assert property(tx_release_gnt_one_same_cycle_tx_eot)
   else
      $error("HTAX_TX_INF ERROR : tx_release_gnt is NOT asserted for one clock cycle or same clock cycle with tx_eot of pkt(t)");


   // ------------------------------------------------------------- 
   // No tx_sot of p(t+1) without tx_eot for p(t)
   // ------------------------------------------------------------- 
   logic tx_eot_seen;
   always_ff@ (posedge clk or negedge rst_n) begin
      if(!rst_n)
         tx_eot_seen <= 1'b1;  //reset to 1'b1
      else if($sampled(tx_eot))
         tx_eot_seen <= 1'b1;
      else if(|$sampled(tx_sot))
         tx_eot_seen <= 1'b0;
   end
   property no_tx_sot_without_tx_eot;
      @(posedge clk) disable iff(!rst_n)
      (|tx_sot) |-> tx_eot_seen;
   endproperty
   assert_no_tx_sot_without_tx_eot : assert property(no_tx_sot_without_tx_eot)
   else
      $error("HTAX_TX_INF ERROR : tx_sot of p(t+1) without tx_eot for p(t)");


   // ------------------------------------------------------------- 
   // Valid packet transfer – rise of tx_outport_req followed by a tx_vc_gnt followed by tx_sot
	// followed by tx_release_gnt followed by tx_eot. Consider the right timings between each event.
   // ------------------------------------------------------------- 
   property valid_packet_transfer;
   @(posedge clk) disable iff(!rst_n)

   $rose(|tx_outport_req)
   |-> ##[1:$] (|tx_vc_gnt)
       ##[1:$]       (|tx_sot)
       ##[0:$]   tx_release_gnt
       ##[0:1]   tx_eot;
   endproperty

   assert_valid_packet_transfer :
      assert property(valid_packet_transfer)
      else
         $error("HTAX_TX_INF ERROR : Invalid Packet Transfer");


endinterface : htax_tx_interface

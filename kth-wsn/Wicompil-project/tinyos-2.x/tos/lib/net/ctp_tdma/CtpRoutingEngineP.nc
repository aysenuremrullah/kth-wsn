#include <Timer.h>
#include <TreeRouting.h>
#include <CollectionDebugMsg.h>
/* $Id: CtpRoutingEngineP.nc,v 1.25 2010-06-29 22:07:49 scipio Exp $ */
/*
 * Copyright (c) 2005 The Regents of the University  of California.  
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * - Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the
 *   distribution.
 * - Neither the name of the University of California nor the names of
 *   its contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL
 * THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */

/** 
 *  The TreeRoutingEngine is responsible for computing the routes for
 *  collection.  It builds a set of trees rooted at specific nodes (roots) and
 *  maintains these trees using information provided by the link estimator on
 *  the quality of one hop links.
 * 
 *  <p>Each node is part of only one tree at any given time, but there is no
 *  difference from the node's point of view of which tree it is part. In other
 *  words, a message is sent towards <i>a</i> root, but which one is not
 *  specified. It is assumed that the roots will work together to have all data
 *  aggregated later if need be.  The tree routing engine's responsibility is
 *  for each node to find the path with the least number of transmissions to
 *  any one root.
 *
 *  <p>The tree is proactively maintained by periodic beacons sent by each
 *  node. These beacons are jittered in time to prevent synchronizations in the
 *  network. All nodes maintain the same <i>average</i> beacon sending rate
 *  (defined by BEACON_INTERVAL +- 50%). The beacon contains the node's parent,
 *  the current hopcount, and the cumulative path quality metric. The metric is
 *  defined as the parent's metric plus the bidirectional quality of the link
 *  between the current node and its parent.  The metric represents the
 *  expected number of transmissions along the path to the root, and is 0 by
 *  definition at the root.
 * 
 *  <p>Every time a node receives an update from a neighbor it records the
 *  information if the node is part of the neighbor table. The neighbor table
 *  keeps the best candidates for being parents i.e., the nodes with the best
 *  path metric. The neighbor table does not store the full path metric,
 *  though. It stores the parent's path metric, and the link quality to the
 *  parent is only added when the information is needed: (i) when choosing a
 *  parent and (ii) when choosing a route. The nodes in the neighbor table are
 *  a subset of the nodes in the link estimator table, as a node is not
 *  admitted in the neighbor table with an estimate of infinity.
 * 
 *  <p>There are two uses for the neighbor table, as mentioned above. The first
 *  one is to select a parent. The parent is just the neighbor with the best
 *  path metric. It serves to define the node's own path metric and hopcount,
 *  and the set of child-parent links is what defines the tree. In a sense the
 *  tree is defined to form a coherent propagation substrate for the path
 *  metrics. The parent is (re)-selected periodically, immediately before a
 *  node sends its own beacon, in the updateRouteTask.
 *  
 *  <p>The second use is to actually choose a next hop towards any root at
 *  message forwarding time.  This need not be the current parent, even though
 *  it is currently implemented as such.
 *
 *  <p>The operation of the routing engine has two main tasks and one main
 *  event: updateRouteTask is called periodically and chooses a new parent;
 *  sendBeaconTask broadcasts the current route information to the neighbors.
 *  The main event is the receiving of a neighbor's beacon, which updates the
 *  neighbor table.
 *  
 *  <p> The interface with the ForwardingEngine occurs through the nextHop()
 *  call.
 * 
 *  <p> Any node can become a root, and routed messages from a subset of the
 *  network will be routed towards it. The RootControl interface allows
 *  setting, unsetting, and querying the root state of a node. By convention,
 *  when a node is root its hopcount and metric are 0, and the parent is
 *  itself. A root always has a valid route, to itself.
 *
 *  @author Rodrigo Fonseca
 *  @author Philip Levis (added trickle-like updates)
 *  Acknowledgment: based on MintRoute, MultiHopLQI, BVR tree construction, Berkeley's MTree
 *                           
 *  @date   $Date: 2010-06-29 22:07:49 $
 *  @see Net2-WG
 */

#include "printf.h"

generic module CtpRoutingEngineP(uint8_t routingTableSize, uint32_t minInterval, uint32_t maxInterval) {
    provides {
        interface UnicastNameFreeRouting as Routing;
        interface RootControl;
        interface CtpInfo;
        interface StdControl;
        interface CtpRoutingPacket;
        interface Init;
    } 
    uses {
        interface AMSend as BeaconSend;
        interface Receive as BeaconReceive;
        interface LinkEstimator;
        interface AMPacket;
        interface SplitControl as RadioControl;
        interface Timer<TMilli> as BeaconTimer;
        interface Timer<TMilli> as RouteTimer;
        interface Timer<TMilli> as MBTimer;
        interface Timer<TMilli> as InitPhaseTimer;  
        //interface Timer<TMilli> as InitPhaseDataTimer;       
        interface Random;
        interface CollectionDebug;
        interface CtpCongestion;
		interface Capisrunning;
		interface CompareBit;
		interface HasTimeSlot;
		interface Leds;
		
    }
}


implementation {

    bool ECNOff = TRUE;

    /* Keeps track of whether the radio is on. No sense updating or sending
     * beacons if radio is off */
    bool radioOn = FALSE;
    /* Controls whether the node's periodic timer will fire. The node will not
     * send any beacon, and will not update the route. Start and stop control this. */
    bool running = FALSE;
    /* Guards the beacon buffer: only one beacon being sent at a time */
    bool sending = FALSE;

    /* Tells updateNeighbor that the parent was just evicted.*/ 
    bool justEvicted = FALSE;
    
    /*Tells whethet the CAP is still on or not (can send the beacon or not)*/
    bool cansend = FALSE;

    /*Tells about the total beacons failed to sent due to CFP interval*/
	uint8_t beacons_not_posted = 0;
	
	// The start of next CAP intercal
	uint32_t nextCapStartat;
	
	// The current time
	uint32_t nowtimeis;
	
	bool reset_trickle_timer = FALSE;
	
    // The Max beacons that not sent due to CFP interval
	uint8_t MAX_BEACON_UNPOST 	= 3;	 
	 	
	uint32_t MB_INIT_PERIOD 	= 10000;  // For the devices
	uint32_t MB_ROOT_INIT_PERIOD = 50000;  // For the sink 
	
    route_info_t routeInfo;
    bool state_is_root;
    am_addr_t my_ll_addr;
    
    // Number of beacons sent with option == 3
    uint16_t HealthBroadcasts_ini, HealthBroadcasts_curr ;

    message_t beaconMsgBuffer;
    ctp_routing_header_t* beaconMsg;

    /* routing table -- routing info about neighbors */
    routing_table_entry routingTable[routingTableSize];
    uint8_t routingTableActive;

	/* keeps track of children */
	child_info childTable[routingTableSize];
	uint8_t childrenInTable; 
	uint8_t children_without_TS;
	uint8_t children_MB_heard;
    bool PS;
	bool first_mb_sent;
    bool init_period_over;
    bool Route_Found;              // Have we found the route to parent yet or not (got TS?)
    
    bool CTP_UN_HEALTHY_flag;	   // For node that does not have parent
    
    bool TX_HEALTHY_AGAIN_flag;		   // If parent of a node has become healthy again		
       
    /* statistics */
    uint32_t parentChanges;
    /* end statistics */

    // forward declarations
    void routingTableInit();
    uint8_t routingTableFind(am_addr_t);
    error_t routingTableUpdateEntry(am_addr_t, am_addr_t , uint16_t , bool);
    error_t routingTableEvict(am_addr_t neighbor);
	
	void childTableInit();
    error_t childrenTableUpdateEntry(am_addr_t, uint8_t);
    uint8_t childTableFind(am_addr_t);
    void childTableClear(void);    

	error_t processMB(am_addr_t);
	void firstTimePS();
	void print_children_table();

	am_addr_t best_neighbor_id;
  	uint16_t best_neighbor_etx;
  	
  	uint8_t parent_table_idx, best_neighbor_table_idx;

	task void updateRouteTask(); //always send the most up to date info
	task void sendBeaconTask();
	task void ImmidiateParentSwitchTask();
	task void ImmidiateSendBeaconTask();
	task void ISBTask();
	
  /* 
     For each interval t, you set a timer to fire between t/2 and t
     (chooseAdvertiseTime), and you wait until t (remainingInterval). Once
     you are at t, you double the interval (decayInterval) if you haven't
     reached the max. For reasons such as topological inconsistency, you
     reset the timer to a small value (resetInterval).
  */

    uint32_t currentInterval = minInterval;
    uint32_t t; 
    bool tHasPassed;

    void chooseAdvertiseTime() {
       t = currentInterval;
       t /= 2;
       t += call Random.rand32() % t;
       tHasPassed = FALSE;
       
       call BeaconTimer.startOneShot(t);       
    }

    void resetInterval() {
      currentInterval = minInterval;
      chooseAdvertiseTime();
    }

    void decayInterval() {
        currentInterval *= 2;
        if (currentInterval > maxInterval) {
          currentInterval = maxInterval;
        }
	    chooseAdvertiseTime();
    }

    void remainingInterval() {
       uint32_t remaining = currentInterval;
       remaining -= t;
       tHasPassed = TRUE;
       call BeaconTimer.startOneShot(remaining);
    }
    
    void delayInterval(){
    	
    	//printf("Inside the delayInterval, timer firing in %i\n ",nextCapStartat - call BeaconTimer.getNow());
    	//printfflush();
    	
        call BeaconTimer.startOneShot( nextCapStartat - call BeaconTimer.getNow() );		
		beacons_not_posted++;				
    }

    command error_t Init.init() {
        uint8_t maxLength;
        radioOn = FALSE;
        running = FALSE;
        parentChanges = 0;
        state_is_root = 0;
	   
	    children_without_TS = 0;
	    children_MB_heard = 0;
        
        PS = FALSE;
        first_mb_sent = FALSE;
        
        routeInfoInit(&routeInfo);
        
        routingTableInit();
        childTableInit();
        
        Route_Found = FALSE;
        init_period_over = FALSE;
 	  	
 	  	CTP_UN_HEALTHY_flag = FALSE;
 	  	TX_HEALTHY_AGAIN_flag = FALSE;
 	  	
 	  	if (call HasTimeSlot.hasTS() != TRUE ){	
 	  		call InitPhaseTimer.startOneShotAt(call InitPhaseTimer.getNow(), MB_INIT_PERIOD + MB_ROOT_INIT_PERIOD);  // If this is the case of dynamic time-slot allocation
 	  	} else { 
			first_mb_sent = TRUE;  																					// If this is the case of static time-slot allocation
 	  		init_period_over = TRUE; 
 	  	}
        
        best_neighbor_id = 0;
  		best_neighbor_etx = 0;
        
        parent_table_idx = 0;
        best_neighbor_table_idx = 255;

    	//uint8_t last_parent_status = 0;      // { 0 IN_THE_NETWORK     1 IN_THE_NETWORK_UNHEALTHY     2 OUT_OF_NETWORK }
        HealthBroadcasts_ini  = 0;
        HealthBroadcasts_curr = 0;
        
        beaconMsg = call BeaconSend.getPayload(&beaconMsgBuffer, call BeaconSend.maxPayloadLength());
        maxLength = call BeaconSend.maxPayloadLength();
        dbg("TreeRoutingCtl","TreeRouting initialized. (used payload:%d max payload:%d!\n", 
              sizeof(beaconMsg), maxLength);
        return SUCCESS;
    }

    command error_t StdControl.start() {
      my_ll_addr = call AMPacket.address();
      //start will (re)start the sending of messages

      if (!running) {
		running = TRUE;
		resetInterval();
		call RouteTimer.startPeriodic(BEACON_INTERVAL);
		dbg("TreeRoutingCtl","%s running: %d radioOn: %d\n", __FUNCTION__, running, radioOn);
      }     

      return SUCCESS;
    }

    command error_t StdControl.stop() {
        running = FALSE;
        dbg("TreeRoutingCtl","%s running: %d radioOn: %d\n", __FUNCTION__, running, radioOn);
        return SUCCESS;
    } 

    event void RadioControl.startDone(error_t error) {
        radioOn = TRUE;
        dbg("TreeRoutingCtl","%s running: %d radioOn: %d\n", __FUNCTION__, running, radioOn);
        if (running) {
            uint16_t nextInt;
            nextInt = call Random.rand16() % BEACON_INTERVAL;
            nextInt += BEACON_INTERVAL >> 1;
        }
    } 

    event void RadioControl.stopDone(error_t error) {
        radioOn = FALSE;
        dbg("TreeRoutingCtl","%s running: %d radioOn: %d\n", __FUNCTION__, running, radioOn);
    }

    /* Is this quality measure better than the minimum threshold? */
    // Implemented assuming quality is EETX
    bool passLinkEtxThreshold(uint16_t etx) {
        return (etx < ETX_THRESHOLD);
    }
	
	/******************************** This is my addition*************************************/

	async event void Capisrunning.Caphasstarted(uint32_t t0 , uint32_t dt){
		
		atomic{
			cansend = TRUE;	
			// current SF time + beacon interval
			nextCapStartat = t0;
			nowtimeis= dt;

  		    //printf("BNP %i\n",beacons_not_posted);
		    //printfflush();

			if(reset_trickle_timer == TRUE){
				
				printf("RE trickle timer reset \n");
				printfflush();
				
				
				reset_trickle_timer = FALSE;
				post sendBeaconTask();
				resetInterval();
			
			}
				
			if (beacons_not_posted > 3){
				  				  
		          post updateRouteTask(); //always send the most up to date info
		          post sendBeaconTask();
			      
				  beacons_not_posted = 0;
				  
				  // We start with the old currentInterval, but stop the timer before that
				  //call BeaconTimer.stop();    
				  
				  decayInterval();
			}
		}
		
		//printf("Inside router CAP started %i,  nextCapStartat %lu , getNow()%lu \n",
		//cansend , nextCapStartat, call BeaconTimer.getNow());
		
		printfflush();
	}

	async event void Capisrunning.Caphasfinished(){
		
		atomic{
			cansend = FALSE;
		}
		
//		printf("Inside router CAP finished %i\n",cansend);
//		printfflush();
	}

	async event void Capisrunning.MyTShasStarted(){	}

	/******************************** This is my addition*************************************/

    /* updates the routing information, using the info that has been received
     * from neighbor beacons. Two things can cause this info to change: 
     * neighbor beacons, changes in link estimates, including neighbor eviction */
    task void updateRouteTask() {
        uint8_t i;
        routing_table_entry* entry;
        routing_table_entry* best;
        uint16_t minEtx;
        uint16_t currentEtx;
        uint16_t linkEtx, pathEtx;

        if (state_is_root)
            return;
       
        best = NULL;
        /* Minimum etx found among neighbors, initially infinity */
        minEtx = MAX_METRIC;
        /* Metric through current parent, initially infinity */
        currentEtx = MAX_METRIC;

        dbg("TreeRouting","%s\n",__FUNCTION__);

        /* Find best path in table, other than our current */

        //printf("/**** Routing table *******/ \n");
        //printf("/**** Routing table *******/ \n");
        //printfflush();

        for (i = 0; i < routingTableActive; i++) {
            entry = &routingTable[i];

            // Avoid bad entries and 1-hop loops
            if (entry->info.parent == INVALID_ADDR || entry->info.parent == my_ll_addr) {
              dbg("TreeRouting", 
                  "routingTable[%d]: neighbor: [id: %d parent: %d  etx: NO ROUTE]\n",  
                  i, entry->neighbor, entry->info.parent);
              continue;
            }

            linkEtx = call LinkEstimator.getLinkQuality(entry->neighbor);
            
            //printf("\n");
            //printf("treeRouting routingtable[%d]: neighbor: [id: %d parent: %d etx: %d retx: %d]\n",  
            //    i, entry->neighbor, entry->info.parent, linkEtx, entry->info.etx);
            //printfflush();    
                
            pathEtx = linkEtx + entry->info.etx;
            /* Operations specific to the current parent */
            if (entry->neighbor == routeInfo.parent) {
            	
       	        parent_table_idx = i;
                   	
                dbg("TreeRouting", "   already parent.\n");
                currentEtx = pathEtx;
                /* update routeInfo with parent's current info */
				
				routeInfo.etx = entry->info.etx;
				routeInfo.congested = entry->info.congested;
                
                continue;
            }
            /* Ignore links that are congested */
            if (entry->info.congested)
                continue;
            /* Ignore links that are bad */
            
            /**if (!passLinkEtxThreshold(linkEtx)) {
              dbg("TreeRouting", "   did not pass threshold.\n");
              continue;
            }**/
            
            if ( (pathEtx < minEtx ) ) {// && ( routingTable[i].info.healthy == TRUE) ) {
	      		dbg("TreeRouting", "   best is %d, setting to %d\n", pathEtx, entry->neighbor);
                minEtx = pathEtx;
                best = entry;
                best_neighbor_table_idx = i;
            } 
        }
	    
	    
	    // If there is a best neighbor
	    if (best !=NULL){    
        	best_neighbor_id = best->neighbor;
  			best_neighbor_etx = minEtx;
        }else{
        	best_neighbor_id  = 50000;
  			best_neighbor_etx = 1000;        	
        }
        
        //printf("RE  MinEtx %i   OwnEtx %i   Parent %i  ParentHealthy %i  BN  %i  BNHealthy %i \n", minEtx , currentEtx , 
        //	routingTable[parent_table_idx].neighbor , routeInfo.healthy , routingTable[best_neighbor_table_idx].neighbor , routingTable[best_neighbor_table_idx].info->healthy);
        //printfflush();	

        /* Now choose between the current parent and the best neighbor */
        /* Requires that: 
            1. at least another neighbor was found with ok quality and not congested
            2. the current parent is congested and the other best route is at least as good
            3. or the current parent is not congested and the neighbor quality is better by 
               the PARENT_SWITCH_THRESHOLD.
          Note: if our parent is congested, in order to avoid forming loops, we try to select
                a node which is not a descendent of our parent. routeInfo.ext is our parent's
                etx. Any descendent will be at least that + 10 (1 hop), so we restrict the 
                selection to be less than that.
        */
        if (minEtx != MAX_METRIC) {
            if (  (currentEtx == MAX_METRIC ||
                (routeInfo.congested && (minEtx < (routeInfo.etx + 10))) ||
                minEtx + PARENT_SWITCH_THRESHOLD < currentEtx)  ) {

                	if ( best->info.healthy == TRUE || PS == FALSE ){
		             
		                //printf("RE We are for parent change \n");
		                //printfflush();
		                	
		                if ( PS == FALSE){  // First parent has not been selected 
		                
			                // It means that we have time slot and the newly proposed parent has time slot after our own
			                // routeInfo.metric will not store the composed metric.
			                // since the linkMetric may change, we will compose whenever
			                // we need it: i. when choosing a parent (here); 
			                //            ii. when choosing a next hop
			                parentChanges++;
			
			                //printf("RE: Changed parent. from %d to %d\n", routeInfo.parent, best->neighbor);
			                //printfflush();
			                
			                call CollectionDebug.logEventDbg(NET_C_TREE_NEW_PARENT, best->neighbor, best->info.etx, minEtx);
			                call LinkEstimator.unpinNeighbor(routeInfo.parent);
			                call LinkEstimator.pinNeighbor(best->neighbor);
			                call LinkEstimator.clearDLQ(best->neighbor);
			
							routeInfo.parent = best->neighbor;
							routeInfo.etx = best->info.etx;
							routeInfo.congested = best->info.congested;
							routeInfo.healthy = TRUE;
							
							if (currentEtx - minEtx > 20) { call CtpInfo.triggerRouteUpdate(); }
							
						} else {   // First parent has been selected 
							if (call HasTimeSlot.hasTS() == FALSE) {}  // we donot have a time slot yet, donot do any thing
							else {   // we has a time slot
								 
								 //printf("own ID %i   best->neighbor %i\n",TOS_NODE_ID, best->neighbor);
								 //printfflush();
								  	
								if (call LinkEstimator.canSelectThisAsParent(TOS_NODE_ID, best->neighbor) == TRUE){  // we can select this neighbor as new parent
			
									parentChanges++;
			
					                //printf("RE: Changed parent. from %d to %d\n", routeInfo.parent, best->neighbor);
					                //printfflush();
					                			                
					                call CollectionDebug.logEventDbg(NET_C_TREE_NEW_PARENT, best->neighbor, best->info.etx, minEtx);
					                call LinkEstimator.unpinNeighbor(routeInfo.parent);
					                call LinkEstimator.pinNeighbor(best->neighbor);
					                call LinkEstimator.clearDLQ(best->neighbor);
					
									routeInfo.parent = best->neighbor;
									routeInfo.etx = best->info.etx;
									routeInfo.congested = best->info.congested;
									
									if (currentEtx - minEtx > 20) { call CtpInfo.triggerRouteUpdate(); }
									
								} else {
									
									// code for neighbor penality so that it cannot be selected any more							
									//printf("this neighbor cannot be selected parent as its timeslot is after our own \n");
									//printfflush();
												
								}  // else, cannot select parent 
						 	} // else, has a time slot
		             } // else, first parent has been selected
		          }    // if (best->info.healthy == TRUE)
		          
		          else{ 
		          	
		          	//printf("RE  Parent selection failed , Best not healthy\n");
		          	//printfflush();
		          	
		          }  // else (best->info.healthy == TRUE)
          
          }// if (currentEtx == MAX_METRIC)
		} // if (minEtx != MAX_METRIC)
		
		
        /* Finally, tell people what happened:  */
        /* We can only loose a route to a parent if it has been evicted. If it hasn't 
         * been just evicted then we already did not have a route */
        if (justEvicted && routeInfo.parent == INVALID_ADDR){ 
        
        	//printf("RE  justEvicted && routeInfo.parent \n");
        	//printfflush();
        
            signal Routing.noRoute();
         }

        /* If we did not have parent and we just have found one right now and also
         * we donot have time slot */

        else if (!justEvicted && 
                  currentEtx == MAX_METRIC &&
                  minEtx != MAX_METRIC &&
                  (call HasTimeSlot.hasTS() == FALSE) ){
                  		
			        	//printf("RoutingEngineP:  PS == true , hasts == FALSE \n");
        				//printfflush();

                  		PS = TRUE;
                  		firstTimePS();	
                 }  // we have found a parent

        /* On the other hand, if we didn't have a parent (no currentEtx) and now we
         * do, then we signal route found. The exception is if we just evicted the 
         * parent and immediately found a replacement route: we don't signal in this 
         * case */

        else if (!justEvicted && 
                  currentEtx == MAX_METRIC &&
                  minEtx != MAX_METRIC &&
                  (call HasTimeSlot.hasTS() == TRUE) ){

		        	//printf("RoutingEngineP:  PS == true , Hasts == true \n");
       				//printfflush();

            		PS = TRUE;
            		signal Routing.routeFound();
            		
            		//printf("routeInfo.parent %i  routeInfo.etx %i \n",routeInfo.parent,routeInfo.etx);
            		//printfflush();
            		
       		      	//call InitPhaseDataTimer.startOneShotAt(call InitPhaseDataTimer.getNow(), MB_INIT_PERIOD);	    			
            		
            }


        justEvicted = FALSE; 
    }

    

    /* send a beacon advertising this node's routeInfo */
    // only posted if running and radioOn
    task void sendBeaconTask() {
        error_t eval;
        if (sending) {
            return;
        }

        beaconMsg->options = 0;

        /* Congestion notification: am I congested? */
        if (call CtpCongestion.isCongested()) {
       
        	//printf("I am congested: sendBeaconTask() \n");
        	//printfflush();
       
            beaconMsg->options |= CTP_OPT_ECN;
        }

		/** If node does not have a TS then **/
		if (call HasTimeSlot.hasTS() == FALSE){
			beaconMsg->options |= CTP_NO_TS;				
			//call CtpRoutingPacket.setTsInfo(beaconMsg,1);
		}
		else {
			//call CtpRoutingPacket.setTsInfo(beaconMsg,0);
		}
		
		/**All children should immidiately change parent or send beacon with this field*/
		if (CTP_UN_HEALTHY_flag == TRUE){
			beaconMsg->options |= CTP_UN_HEALTHY;
		}
		
		
		// If our parent becomes healthy again
		/**if (TX_HEALTHY_AGAIN_flag == TRUE){
			
			if ((HealthBroadcasts_curr - HealthBroadcasts_ini) < 5 ){   // We Tx 5 consecutive beacons with options CTP_HEALTHY_AGAIN 
				
				beaconMsg->options |= CTP_HEALTHY_AGAIN;
				HealthBroadcasts_curr++;
			
			} else if( (HealthBroadcasts_curr - HealthBroadcasts_ini) >= 5 && ((HealthBroadcasts_curr - HealthBroadcasts_ini) < 10 ) ){  // Buffer period of 5 beacons
				HealthBroadcasts_curr++;
			}  
			else{    // Now we lower the flag TX_HEALTHY_AGAIN_flag
				HealthBroadcasts_ini = HealthBroadcasts_curr;
				TX_HEALTHY_AGAIN_flag = FALSE;
			}
			
		}**/
		
        beaconMsg->parent = routeInfo.parent;
        if (state_is_root) {
            beaconMsg->etx = routeInfo.etx;
        }
        else if (routeInfo.parent == INVALID_ADDR) {
            beaconMsg->etx = routeInfo.etx;
            beaconMsg->options |= CTP_OPT_PULL;
        } else {
            beaconMsg->etx = routeInfo.etx + call LinkEstimator.getLinkQuality(routeInfo.parent);
        }
	
          //printf("Beacon transmitted with Etx  %i   options  %i \n",beaconMsg->etx, beaconMsg->options);
          //printfflush();

        //printf("treeRouting parent (sending): %d etx: %d\n",
        //          beaconMsg->parent, beaconMsg->etx);
        //printfflush();          

        call CollectionDebug.logEventRoute(NET_C_TREE_SENT_BEACON, beaconMsg->parent, 0, beaconMsg->etx);

        eval = call BeaconSend.send(AM_BROADCAST_ADDR, 
                                    &beaconMsgBuffer, 
                                    sizeof(ctp_routing_header_t));
        if (eval == SUCCESS) {
            sending = TRUE;
        } else if (eval == EOFF) {
            radioOn = FALSE;
            dbg("TreeRoutingCtl","%s running: %d radioOn: %d\n", __FUNCTION__, running, radioOn);
        }
    }

    event void BeaconSend.sendDone(message_t* msg, error_t error) {
        if ((msg != &beaconMsgBuffer) || !sending) {
        	
        	//printf("Beacon not sent\n");
        	//printfflush();
        	
            //something smells bad around here
            return;
        }
        sending = FALSE;
    }

    event void RouteTimer.fired() {
      
      if (radioOn && running) {
 	     //print_children_table();
 	     
 	     if (first_mb_sent == TRUE) {   // first beacon has already been sent
 	
 	     	if (call HasTimeSlot.hasTS() == TRUE){	 // if we have a time slot
 
 	     		if (Route_Found == FALSE) {      // If this is the first time we are here
 	     			Route_Found = TRUE;
 	     			signal Routing.routeFound();
 	     		} else {}    // else just continue
 	     		
 	     	} else {   // if we donot have a time ,slot yet
 	     	
 	     		if (init_period_over == FALSE){  }  // Initialization phase is not over
 	     		else {                              // Initialization period is  over
 	     			init_period_over = FALSE;
        			call InitPhaseTimer.startOneShotAt(call InitPhaseTimer.getNow(), MB_INIT_PERIOD);            
 	     			call LinkEstimator.canTxMB(routeInfo.parent, first_mb_sent, TRUE);  // Here we are re-transmiting the MB
 	     		} // else, the init period is over	
 	     		 	     			
 	     	} // else, we donot have a time slot
 	     }  //  if (first_mb_sent == TRUE)
         
         post updateRouteTask();
      } // if (radioOn && running)
      
    }

	/******************************** This is my addition*************************************/

      
    event void BeaconTimer.fired() {
      if (radioOn && running) {
      	
		//printf("Beacon timer fired , cansend %i, beacons_not_posted %i \n",cansend, beacons_not_posted);	
		//printfflush();      	

      	if (cansend){  // CAP is running
	      	atomic{
			        if (!tHasPassed) {  
			          post updateRouteTask(); //always send the most up to date info
			          post sendBeaconTask();
			          
			          beacons_not_posted = 0;

			          dbg("RoutingTimer", "Beacon timer fired at %s\n", sim_time_string());
			          remainingInterval();
			        }
			        else {
			          decayInterval();
			        }
				 }   
		} else {   // CAP is finished and CFP has started
			
			if (!tHasPassed) { 
				remainingInterval(); 
				//delayInterval();  // Wait for the next CAP
			} 
			else {
				beacons_not_posted++;
		    	chooseAdvertiseTime();  // Run over the same window length
		    }
		}
		   
      }
   }

	/******************************** This is my addition*************************************/

    ctp_routing_header_t* getHeader(message_t* ONE m) {
      return (ctp_routing_header_t*)call BeaconSend.getPayload(m, call BeaconSend.maxPayloadLength());
    }
    
    
    /* Handle the receiving of beacon messages from the neighbors. We update the
     * table, but wait for the next route update to choose a new parent */
   
   event message_t* BeaconReceive.receive(message_t* msg, void* payload, uint8_t len) {
        am_addr_t from;
        ctp_routing_header_t* rcvBeacon;
        bool congested;
        uint16_t pathEtx;
        uint8_t idx;

        // Received a beacon, but it's not from us.
        if (len != sizeof(ctp_routing_header_t)) {
          dbg("LITest", "%s, received beacon of size %hhu, expected %i\n",
                     __FUNCTION__, 
                     len,
                     (int)sizeof(ctp_routing_header_t));
              
          return msg;
        }
        
        //need to get the am_addr_t of the source
        from = call AMPacket.source(msg);
                
        rcvBeacon = (ctp_routing_header_t*)payload;

        //printf("RE: T Received beacon from node   %i  parent %i  options %x  etx %i \n",from,rcvBeacon->parent,rcvBeacon->options,rcvBeacon->etx);
        //printfflush();

        congested = call CtpRoutingPacket.getOption(msg, CTP_OPT_ECN);

        if (rcvBeacon->parent == TOS_NODE_ID){
            childrenTableUpdateEntry( call AMPacket.source(msg), call CtpRoutingPacket.getTsInfo(msg) );
        }

        dbg("TreeRouting","%s from: %d  [ parent: %d etx: %d]\n",
            __FUNCTION__, from, 
            rcvBeacon->parent, rcvBeacon->etx);

        	

//        if( ( my_ll_addr == 2 && (from != 1) ) ||
//        	( my_ll_addr == 3 && (from != 1) ) ||
//        	( my_ll_addr == 4 && (from != 2) ) ||
//        	( my_ll_addr == 5 && (from != 3) ) ||
//        	( my_ll_addr == 6 && (from != 4) ) ||
//	       	( my_ll_addr == 7 && (from != 5) ) || 
//	       	( my_ll_addr == 8 && (from != 6) ) ||
//	       	( my_ll_addr == 9 && (from != 7) ) ||
//    	   	( my_ll_addr == 10 && ( (from == 1) || (from == 2) || (from == 3) || (from == 4) || (from == 5) || (from == 6) || (from == 7)) )
//       	){


        if( ( my_ll_addr == 2 && (from != 1) ) ||
        	( my_ll_addr == 3 && (from != 1) ) ||
        	( my_ll_addr == 4 && (from != 2) ) ||
        	( my_ll_addr == 5 && (from != 3) ) ||
        	( my_ll_addr == 6 && (from != 4) ) ||
	       	( my_ll_addr == 7 && (from != 5) ) || 
	       	( my_ll_addr == 8 && ( (from == 1) || (from == 2) || (from == 3) || (from == 4) || (from == 5) ) )
       	){
	
/**        if( ( my_ll_addr == 2 && (from != 1) ) ||
        	( my_ll_addr == 3 && (from != 1) ) ||
        	( my_ll_addr == 4 && (from != 2) ) ||
        	( my_ll_addr == 5 && (from != 3) ) ||
    	   	( my_ll_addr == 6 && ( (from == 1) || (from == 2) || (from == 3) ) )
       	){	**/

        /**if( ( my_ll_addr == 2 && (from != 1) ) ||
        	( my_ll_addr == 3 && (from != 2) ) ||
        	( my_ll_addr == 4 && (from != 2) ) ||
    	   	( my_ll_addr == 5 && ( (from == 1) || (from == 2) ) )
       	){	**/

		//if( ( my_ll_addr == 4 && (from == 1) ) ){

        /**if( ( my_ll_addr == 2 && (from != 1) ) ||
        	( my_ll_addr == 3 && (from != 2) )
    	   	){**/
			
			//printf("RE Beacon not from what we wanted \n");
			//printfflush();
			
       		if (call CtpRoutingPacket.getOption(msg, CTP_OPT_PULL)) { 
	        	
	        	//printf("RE trickle timers reset from inside the barred beacon receiver \n");
	        	//printfflush();
	        	
	        	resetInterval();
	        }
       	}

       else {
       		//printf("RE T beacon not barred \n");
       		//printfflush();
	        //update neighbor table
	        if (rcvBeacon->parent != INVALID_ADDR) {
	        	
	            /* If this node is a root, request a forced insert in the link
	             * estimator table and pin the node. */
	            if (rcvBeacon->etx == 0) {
	           		// These cannot be neighbor of root
	                call LinkEstimator.insertNeighbor(from);
	                call LinkEstimator.pinNeighbor(from);
	  
	            }
	            //TODO: also, if better than my current parent's path etx, insert
				
				// This is a hack for quick ETX and parent update 
				if (from == routeInfo.parent){ 

					idx = routingTableFind(routeInfo.parent);
					
					//printf("RE quick etx fix for parent %i   Etx %i  Options %i \n", routingTable[idx].neighbor, rcvBeacon->etx, rcvBeacon->options);
					//printfflush();

					routeInfo.etx = rcvBeacon->etx;

					// The parent that was not heard and was declared unhealthy
					// was heard again and was declared healthy
					// Time to rest the trickle timer and send the beacon with flag CTP_HEALTHY_AGAIN 

					if ( ((rcvBeacon->options &= CTP_HOW_MANY ) == 0) && (routingTable[idx].info.healthy == FALSE) ){ 
					
	            		CTP_UN_HEALTHY_flag = FALSE;		            		            		
						routingTable[idx].info.healthy = TRUE;
					    
					    call Leds.led0Off();
				      	
				      	printf("RE  unheard parent heard again and declared healthy \n");
				      	printfflush();	
						
			      		currentInterval = minInterval;      	
			      		reset_trickle_timer = TRUE;	 
			      		
			      		post updateRouteTask();
				      	
					} 
					// The parent is unhealthy but in the network
					if ( (rcvBeacon->options &= CTP_UN_HEALTHY) == 2 ){   // We have 
				
					  printf("RE  Parent %i declared unhealthy inside beacon rx \n",routingTable[idx].neighbor);
					  printfflush();
					  					  	
			      	  routingTable[parent_table_idx].info.healthy = FALSE;		      

					  if ( (best_neighbor_id > 0 && best_neighbor_id < 1000) && CTP_UN_HEALTHY_flag == FALSE ){   // We have a valid neighbor and we have not reset the interval yet
						post ImmidiateParentSwitchTask();
					  } else { // We donot have a valid neighbor
					  	call Leds.led0On();
						post ImmidiateSendBeaconTask();
					  }		
						
					  post updateRouteTask();				
								
					} 
															
				}	        
				
				
        		
        		if ( (rcvBeacon->options &= CTP_HOW_MANY ) == 0){
            		routingTableUpdateEntry(from, rcvBeacon->parent, rcvBeacon->etx, TRUE);
            	} else {
            		routingTableUpdateEntry(from, rcvBeacon->parent, rcvBeacon->etx, FALSE);
            	}
	            	
	            	
	            	
	            	            	            
	            /* This is my child*/
	            if (rcvBeacon->parent == TOS_NODE_ID){
		            childrenTableUpdateEntry( call AMPacket.source(msg), call CtpRoutingPacket.getTsInfo(msg) );
	            }
	            
	            call CtpInfo.setNeighborCongested(from, congested);
	        }
	
	        if (call CtpRoutingPacket.getOption(msg, CTP_OPT_PULL)) { 
	        	
	        	//printf("RE trickle timers reset from inside the beacon receiver \n");
	        	//printfflush();
	        	
	        	resetInterval();
	        	childTableClear();  // Clear the child table
	        }
	         
       } 
         
        return msg;
    }


    /* Signals that a neighbor is no longer reachable. need special care if
     * that neighbor is our parent */
    event void LinkEstimator.evicted(am_addr_t neighbor) {
        routingTableEvict(neighbor);
        dbg("TreeRouting","%s\n",__FUNCTION__);
        
        //printf("RE Node evicted from the routing table \n");
        //printfflush();
        
        if (routeInfo.parent == neighbor) {
            routeInfoInit(&routeInfo);
            justEvicted = TRUE;
            post updateRouteTask();
        }
    }

	/***********************************************************************************/
	
	event void LinkEstimator.receivedMB(am_addr_t neighbor){
		processMB(neighbor);
		//return SUCCESS;
	}

    /* Interface UnicastNameFreeRouting */
    /* Simple implementation: return the current routeInfo */
    command am_addr_t Routing.nextHop() {
        return routeInfo.parent;    
    }
    command bool Routing.hasRoute() {
        return (routeInfo.parent != INVALID_ADDR);
    }
   
    /* CtpInfo interface */
    command error_t CtpInfo.getParent(am_addr_t* parent) {
        if (parent == NULL) 
            return FAIL;
        if (routeInfo.parent == INVALID_ADDR)    
            return FAIL;
        *parent = routeInfo.parent;		    	
        
        return SUCCESS;
    }

    command error_t CtpInfo.getEtx(uint16_t* etx) {
        if (etx == NULL) 
            return FAIL;
        if (routeInfo.parent == INVALID_ADDR)    
            return FAIL;
	if (state_is_root == 1) {
	  *etx = 0;
	} else {
	  *etx = routeInfo.etx + call LinkEstimator.getLinkQuality(routeInfo.parent);
	}
        return SUCCESS;
    }

    command void CtpInfo.recomputeRoutes() {
    
      //printf("RE   CtpInfo.recomputeRoutes \n");
      //printfflush();
      	
      post updateRouteTask();
    }

    command void CtpInfo.triggerRouteUpdate() {
      resetInterval();
     }

	/******************************* Loop detection / Immidiate route update code**********************************/

    command void CtpInfo.triggerImmediateRouteUpdate(uint8_t what) {
      
      uint8_t idx;
      
      printf("RE  CtpInfo.triggerImmediateRouteUpdate   options %i\n",what);
      printfflush();
      
      //if (call InitPhaseDataTimer.isRunning()){}
      //else{ 
    
      	if (what == 0) {  // Loop detection due to wrong ETX information, parent still healthy
      		
      		//printf("RE wrong loop detection due to beacon based Etx increase \n");
      		//printfflush();
      		
	      	//printf("RE resetInterval() \n");
	      	//printfflush();	
			
	      	//currentInterval = minInterval;      	
	      	//reset_trickle_timer = TRUE;	 
	      	     	
      	} 
      	
      	else if (what == 1){  // Immidiate parent switch

			idx = routingTableFind(routeInfo.parent);
			routingTable[idx].info.healthy = FALSE;
			
	        printf("RE Immidiate Parent Change \n");
	        printfflush();
      		  	      	
      		post ImmidiateParentSwitchTask();
      	}
      	 
      	else if (what == 2) {    // Donot have a best neighbor, immidiate beacon send with CTP_UN_HEALTHY

			idx = routingTableFind(routeInfo.parent);
			routingTable[idx].info.healthy = FALSE;

           	printf("RE Immidiate Beacon Sending \n");
           	printfflush();
      	   	
      	   	call Leds.led0On();
      	   	
      		post ImmidiateSendBeaconTask();
      	}
      	else {}
      	    	 
      //}
      
     }

	task void ImmidiateParentSwitchTask(){
		 
		 //printf("Immidiate parent switch task  called \n");
		 //printfflush();
		 	
	     if( PS == TRUE ) {
	    	
	    	CTP_UN_HEALTHY_flag = FALSE;
	    						                			                
	    	// Change to the best neighbor (the first node in the routing table with HEALTHY flag set to true)

	        call LinkEstimator.unpinNeighbor(routeInfo.parent);
	        call LinkEstimator.pinNeighbor(best_neighbor_id);
	        call LinkEstimator.clearDLQ(best_neighbor_id);
			
			if (best_neighbor_id < 1000){ // a valid neighbor
			
				routeInfo.parent = best_neighbor_id;
				routeInfo.etx = best_neighbor_etx;
				routeInfo.congested = FALSE;
	
	  			parentChanges++;
	
				//printf("Parent Switch done from %i  to %i \n",routeInfo.parent, best_neighbor_id);
				//printfflush();
				
			} else {
				// Code for stopping the transmission
			}
									
		}    		
	
	}

	task void ImmidiateSendBeaconTask(){
		
		printf("Immidiate send beacon task called  CAP ON %i \n",cansend);
		printfflush();		
		
		if (cansend){

			CTP_UN_HEALTHY_flag = TRUE;					
			
			post ISBTask();
		
		}
		else{		
		
			CTP_UN_HEALTHY_flag = TRUE;						
			currentInterval = minInterval;
			reset_trickle_timer = TRUE;			

		}		
   }

	task void ISBTask(){
		atomic{			
			error_t eval;
			
		    if (sending) { return; }		
	        
	        beaconMsg->options = 0;			
			beaconMsg->options |= CTP_UN_HEALTHY;				
	        beaconMsg->parent = routeInfo.parent;		        
            beaconMsg->etx = routeInfo.etx + call LinkEstimator.getLinkQuality(routeInfo.parent);
			
	        eval = call BeaconSend.send(AM_BROADCAST_ADDR, 
	                                    &beaconMsgBuffer, 
	                                    sizeof(ctp_routing_header_t));
	                                    
	        if (eval == SUCCESS) {sending = TRUE;} 
	        else if (eval == EOFF) { radioOn = FALSE; reset_trickle_timer = TRUE; }
	        
	        reset_trickle_timer = TRUE;	
	        currentInterval = minInterval;
			//call InitPhaseDataTimer.startOneShotAt(call InitPhaseDataTimer.getNow(), MB_INIT_PERIOD);	

		}
	} 
	


   	//event void InitPhaseDataTimer.fired(){}

	/******************************* Loop detection / Immidiate route update code**********************************/

    command void CtpInfo.setNeighborCongested(am_addr_t n, bool congested) {
        uint8_t idx;    
        if (ECNOff)
            return;
        idx = routingTableFind(n);
        if (idx < routingTableActive) {
            routingTable[idx].info.congested = congested;
        }
        if (routeInfo.congested && !congested) 
            post updateRouteTask();
        else if (routeInfo.parent == n && congested) 
            post updateRouteTask();
    }

    command bool CtpInfo.isNeighborCongested(am_addr_t n) {
        uint8_t idx;    

        if (ECNOff) 
            return FALSE;

        idx = routingTableFind(n);
        if (idx < routingTableActive) {
            return routingTable[idx].info.congested;
        }
        return FALSE;
    }
    
    command error_t CtpInfo.getBestNeighborID(am_addr_t* bn_id){

       *bn_id = best_neighbor_id;

        return SUCCESS;    	
    }
    


    command error_t CtpInfo.getBestNeighborEtx(uint16_t* bn_etx) {        
		
		if (state_is_root == 1) { *bn_etx = 0; } 
		else { *bn_etx = best_neighbor_etx; }
    	
    	return SUCCESS;
    }
    
    /* RootControl interface */
    /** sets the current node as a root, if not already a root */
    /*  returns FAIL if it's not possible for some reason      */
    command error_t RootControl.setRoot() {
        bool route_found = FALSE;
        route_found = (routeInfo.parent == INVALID_ADDR);

		state_is_root = 1;
		routeInfo.parent = my_ll_addr; //myself
		routeInfo.etx = 0;

        if (route_found) 
            signal Routing.routeFound();
        dbg("TreeRouting","%s I'm a root now!\n",__FUNCTION__);
        call CollectionDebug.logEventRoute(NET_C_TREE_NEW_PARENT, routeInfo.parent, 0, routeInfo.etx);
        
        /** This is my change **/              
        call MBTimer.startOneShotAt(call MBTimer.getNow(), MB_ROOT_INIT_PERIOD);       
        /** This is my change **/   
                 
        return SUCCESS;
    }

    command error_t RootControl.unsetRoot() {
      state_is_root = 0;
      routeInfoInit(&routeInfo);

      dbg("TreeRouting","%s I'm not a root now!\n",__FUNCTION__);
      post updateRouteTask();
      return SUCCESS;
    }

    command bool RootControl.isRoot() {
        return state_is_root;
    }

    default event void Routing.noRoute() {
    }
    
    default event void Routing.routeFound() {
    }


  /* The link will be recommended for insertion if it is better* than some
   * link in the routing table that is not our parent.
   * We are comparing the path quality up to the node, and ignoring the link
   * quality from us to the node. This is because of a couple of things:
   *   1. we expect this call only for links with white bit set
   *   2. we are being optimistic to the nodes in the table, by ignoring the
   *      1-hop quality to them (which means we are assuming it's 1 as well)
   *      This actually sets the bar a little higher for replacement
   *   3. this is faster
   */
    event bool CompareBit.shouldInsert(message_t *msg, void* payload, uint8_t len) {
        
        bool found = FALSE;
        uint16_t pathEtx;
        uint16_t neighEtx;
        int i;
        routing_table_entry* entry;
        ctp_routing_header_t* rcvBeacon;

        if ((call AMPacket.type(msg) != AM_CTP_ROUTING) ||
            (len != sizeof(ctp_routing_header_t))) 
            return FALSE;

        /* 1.determine this packet's path quality */
        rcvBeacon = (ctp_routing_header_t*)payload;

        if (rcvBeacon->parent == INVALID_ADDR)
            return FALSE;
        /* the node is a root, recommend insertion! */
        if (rcvBeacon->etx == 0) {
            return TRUE;
        }
    
        pathEtx = rcvBeacon->etx; // + linkEtx;

        /* 2. see if we find some neighbor that is worse */
        for (i = 0; i < routingTableActive && !found; i++) {
            entry = &routingTable[i];
            //ignore parent, since we can't replace it
            if (entry->neighbor == routeInfo.parent)
                continue;
            neighEtx = entry->info.etx;
            found |= (pathEtx < neighEtx); 
        }
        return found;
    }


    /************************* start of routing table functions ************************/
    /* Routing Table Functions                                  */

    /* The routing table keeps info about neighbor's route_info,
     * and is used when choosing a parent.
     * The table is simple: 
     *   - not fragmented (all entries in 0..routingTableActive)
     *   - not ordered
     *   - no replacement: eviction follows the LinkEstimator table
     */

    void routingTableInit() {
        routingTableActive = 0;
    }

    /* Returns the index of parent in the table or
     * routingTableActive if not found */
    uint8_t routingTableFind(am_addr_t neighbor) {
        uint8_t i;
        if (neighbor == INVALID_ADDR)
            return routingTableActive;
        for (i = 0; i < routingTableActive; i++) {
            if (routingTable[i].neighbor == neighbor)
                break;
        }
        return i;
    }


    error_t routingTableUpdateEntry(am_addr_t from, am_addr_t parent, uint16_t etx, bool isHealthy)    {
        uint8_t idx;
        uint16_t  linkEtx;
        linkEtx = call LinkEstimator.getLinkQuality(from);

        idx = routingTableFind(from);
        
        if (idx == routingTableSize) {
        	
            //not found and table is full
            //if (passLinkEtxThreshold(linkEtx))
                //TODO: add replacement here, replace the worst
            //}
            dbg("TreeRouting", "%s FAIL, table full\n", __FUNCTION__);
            return FAIL;
        }
        else if (idx == routingTableActive) {
            //not found and there is space
            if (passLinkEtxThreshold(linkEtx)) {
            	
			      routingTable[idx].neighbor = from;
			      routingTable[idx].info.parent = parent;
			      routingTable[idx].info.etx = etx;
			      //routingTable[idx].info.lastHeardEtx = etx;
			      routingTable[idx].info.haveHeard = 1;
			      routingTable[idx].info.congested = FALSE;
			      routingTable[idx].info.healthy = TRUE;		      

			      routingTableActive++;
	
			      dbg("TreeRouting", "%s OK, new entry\n", __FUNCTION__);

            } else {
                //printf("RE link quality %i below threshold \n",linkEtx);
                //printfflush();
            }
            
        } else {
            //found, just update
		  	routingTable[idx].neighbor = from;
		  	routingTable[idx].info.parent = parent;
		  	routingTable[idx].info.etx = etx;
		  	//routingTable[idx].info.lastHeardEtx = etx;
		  	routingTable[idx].info.haveHeard = 1;	  
		  	routingTable[idx].info.healthy = isHealthy;
		  	
		  	dbg("TreeRouting", "%s OK, updated entry\n", __FUNCTION__);
        }
        return SUCCESS;
    }

    /* if this gets expensive, introduce indirection through an array of pointers */
    error_t routingTableEvict(am_addr_t neighbor) {
        uint8_t idx,i;
        idx = routingTableFind(neighbor);
        if (idx == routingTableActive) 
            return FAIL;
        routingTableActive--;
        for (i = idx; i < routingTableActive; i++) {
            routingTable[i] = routingTable[i+1];    
        } 
        return SUCCESS; 
    }
        
    /********************** For keeping track of the children starts *************************/
    /* Here are the functions used for managing the data for the children*/ 

    void childTableInit() { 
    	uint8_t  i;
    	childrenInTable = 0;
    	for (i = 0; i < routingTableSize; i++) {
	      	childTable[i].child = 0xFFFF;
	      	childTable[i].hasTimeSlot = FALSE;
	      	childTable[i].heardMB = FALSE;	      	    		
        }    	
    	children_without_TS = 0;
	    children_MB_heard = 0;    	 
    }
     
     
     
    uint8_t childTableFind(am_addr_t neighbor) {
        uint8_t i;
        if (neighbor == INVALID_ADDR)
            return routingTableActive;
        for (i = 0; i < childrenInTable; i++) {
            if (childTable[i].child == neighbor)
                break;
        }
        return i;
    }
   
   
   
    error_t childrenTableUpdateEntry(am_addr_t from, uint8_t hasts){
        uint8_t idx;
        idx = childTableFind(from);
        
        if (idx == routingTableSize) {
            return FAIL;
        }
        else if (idx == childrenInTable) {
            //not found and there is space
	      	childTable[idx].child = from;
	      	
	      	if (hasts == 1){  //  1 in the last bit of the option field (new joiner) means, no TS
	      		childTable[idx].hasTimeSlot = FALSE;
	      	}
	      	else{  // 0 in the last bit of the option field (usual case) means, have a TS
	      		childTable[idx].hasTimeSlot = TRUE;
	      	}
	      			      	
	      	childrenInTable++;
        }
        else { 
        	//found, just update
	      	childTable[idx].child = from;      	
	      		      	
	      	if (hasts == 1){  //  1 in the last bit of the option field (new joiner) means, no TS
	      		childTable[idx].hasTimeSlot = FALSE;
	      	}
	      	else{   // 0 in the last bit of the option field (usual case) means, have a TS
	      		childTable[idx].hasTimeSlot = TRUE;
	      	}
	      	
        }
        return SUCCESS;
    }
    
    
    
    void childTableClear(){
    	uint8_t i;
    	childrenInTable = 0;
    	for (i = 0; i < routingTableSize; i++) {
	      	childTable[i].child = 0xFFFF;
	      	childTable[i].hasTimeSlot = FALSE;
	      	childTable[i].heardMB = FALSE;	      	    		
        }    	 
    }

   
    /************************** Start of special helping functions ******************************/
    /* things to do when LE tells about the modified beacon reception */
    error_t processMB(am_addr_t from){
       uint8_t idx;
       idx = childTableFind(from);
       
       //print_children_table(); 
        
       if (idx == routingTableSize) { 
       		
       		//printf("RE: Child table full \n");
       		//printfflush();
       		
       		return FAIL;
       }
       
       if (idx == childrenInTable) { 
       		
       		//printf("RE: Child not found in table, making a new entry no. %i\n",childrenInTable);
       		//printfflush();
       		
	      	childTable[idx].child = from;	      	
      		childTable[idx].hasTimeSlot = FALSE;
       		childTable[idx].heardMB = TRUE;
       		childrenInTable++;   		
       }
       if (idx < childrenInTable) {
       		
       		//printf("RE: Child found in table at %i\n",idx);
       		//printfflush();
         	childTable[idx].child = from;
        	childTable[idx].hasTimeSlot = FALSE; 
       		childTable[idx].heardMB = TRUE;
       }
        
        /*Now check if we were waiting in the intial waiting phase after parent
         * selection, and now we have heard MB from all of our children*/
        if(state_is_root == FALSE){   // This is not the Sink / Coordinator
	        if (first_mb_sent == FALSE){ 
	        	
	        	//printf("RE: first mb not sent, waiting %i\n",idx);
       			//printfflush();
	        
	        	return SUCCESS; 
	        }    	// Either the parent has not been selected yet or the MBTimer is running	
	        if (first_mb_sent == TRUE){			  				// This is the case when the first Modified beacon 

	        	//printf("RE: first mb sent, LE can send %i\n",idx);
       			//printfflush();
       				        
	        	call LinkEstimator.canTxMB(routeInfo.parent, first_mb_sent, FALSE);   // has already been sent by us. Just tell the LE to
	        	
	        	//printf("RE: after cantxMB \n");
	        	//printfflush();
	        	
	        	return SUCCESS;									// transmit the current request
	        }									 
    	} else {  // This is the Sink / Coordinator
        		if (call MBTimer.isRunning()) { return SUCCESS; }  			// During the initializing phase
        		else {call LinkEstimator.PassMsgToMAC(); return SUCCESS; }	// Tell the LE to transmit the MB
    	}
    	
    	return SUCCESS;	
    }
    

	/* This function tell what to do in case of first time parent selection */
	void firstTimePS(){       
	   call MBTimer.startOneShotAt(call MBTimer.getNow(),MB_INIT_PERIOD + 2000*TOS_NODE_ID);
	}
    
    /* Timer for controlling the first time modified beacon transmission / reception */
    event void MBTimer.fired(){
    	if (state_is_root){        // If this is rootcall MBTimer.isRunning()
    		
    		//printf("RE:MB timer fired in Sink \n");
    		//printfflush();
    		
    		call LinkEstimator.PassMsgToMAC();    	 
    	} else {				  // If this is not a root	
	    	if (first_mb_sent == FALSE){ 
	    		
	    		first_mb_sent = TRUE;
	    		
	        	//printf("RE: MB timer fired  \n");
       			//printfflush();
	    		
	    		call LinkEstimator.canTxMB(routeInfo.parent,first_mb_sent, FALSE); 
	    	}
    	}
    } 

  event void InitPhaseTimer.fired(){
  	init_period_over = TRUE;
  }

	void print_children_table(){	
		uint8_t i;
		//printf("\n");
		//printf("Printing the neighbor table \n");
		//printfflush();
	    
	    for (i = 0; i < childrenInTable; i++) {
	      	//printf("Child ID %i  has time-slot %i  heardMB %i \n",childTable[i].child, childTable[i].hasTimeSlot, childTable[i].heardMB);
	      	//printfflush();	      	    		
        } 
        
        //printf("\n");
       // printfflush();
	}


   /************************ end of special helping functions ******************************/

    /* Default implementations for CollectionDebug calls.
     * These allow CollectionDebug not to be wired to anything if debugging
     * is not desired. */

    default command error_t CollectionDebug.logEvent(uint8_t type) {
        return SUCCESS;
    }
    default command error_t CollectionDebug.logEventSimple(uint8_t type, uint16_t arg) {
        return SUCCESS;
    }
    default command error_t CollectionDebug.logEventDbg(uint8_t type, uint16_t arg1, uint16_t arg2, uint16_t arg3) {
        return SUCCESS;
    }
    default command error_t CollectionDebug.logEventMsg(uint8_t type, uint16_t msg, am_addr_t origin, am_addr_t node) {
        return SUCCESS;
    }
    default command error_t CollectionDebug.logEventRoute(uint8_t type, am_addr_t parent, uint8_t hopcount, uint16_t etx) {
        return SUCCESS;
    }

    command bool CtpRoutingPacket.getOption(message_t* msg, ctp_options_t opt) {    	
      return ( ( (getHeader(msg)->options & CTP_PULL_ECN  ) & opt ) == opt) ? TRUE : FALSE;
    }

    command void CtpRoutingPacket.setOption(message_t* msg, ctp_options_t opt) {
      getHeader(msg)->options |= opt;
    }

    command void CtpRoutingPacket.clearOption(message_t* msg, ctp_options_t opt) {
      getHeader(msg)->options &= ~opt;
    }

    command void CtpRoutingPacket.clearOptions(message_t* msg) {
      getHeader(msg)->options = 0;
    }

    
    command am_addr_t     CtpRoutingPacket.getParent(message_t* msg) {
      return getHeader(msg)->parent;
    }
    command void          CtpRoutingPacket.setParent(message_t* msg, am_addr_t addr) {
      getHeader(msg)->parent = addr;
    }
    
    command uint16_t      CtpRoutingPacket.getEtx(message_t* msg) {
      return getHeader(msg)->etx;
    }
    command void          CtpRoutingPacket.setEtx(message_t* msg, uint16_t etx) {
      getHeader(msg)->etx = etx;
    }

    command uint8_t CtpInfo.numNeighbors() {
      return routingTableActive;
    }
    command uint16_t CtpInfo.getNeighborLinkQuality(uint8_t n) {
      return (n < routingTableActive)? call LinkEstimator.getLinkQuality(routingTable[n].neighbor):0xffff;
    }
    command uint16_t CtpInfo.getNeighborRouteQuality(uint8_t n) {
      return (n < routingTableActive)? call LinkEstimator.getLinkQuality(routingTable[n].neighbor) + routingTable[n].info.etx:0xfffff;
    }
    command am_addr_t CtpInfo.getNeighborAddr(uint8_t n) {
      return (n < routingTableActive)? routingTable[n].neighbor:AM_BROADCAST_ADDR;
    }
    
    command void CtpRoutingPacket.setTsInfo(message_t* msg, uint8_t opt){
    	getHeader(msg)->options |= opt;
    }

    command uint8_t CtpRoutingPacket.getTsInfo(message_t* msg){
    	uint8_t opt = 1;
    	return getHeader(msg)->options &= opt;
    }

    	
} 

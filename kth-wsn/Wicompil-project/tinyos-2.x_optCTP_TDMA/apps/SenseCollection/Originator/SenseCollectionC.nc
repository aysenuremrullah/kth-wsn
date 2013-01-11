#include <Timer.h>
#include "EColl.h"
#include "printf.h"
#include "TreeRouting.h"
#include "CC2420.h"
#include "UserButton.h"

module SenseCollectionC {
  uses interface Boot;
  uses interface SplitControl as RadioControl;
  uses interface StdControl as RoutingControl;
  uses interface Send;
  uses interface Leds;
 
  uses interface RootControl;
  uses interface Receive;
  uses interface Capisrunning;
  
  /* uses interface Resource; */
  /* uses interface Msp430Adc12MultiChannel as MultiChannel; */
  uses interface Notify<button_state_t> as UserButton;
  /* provides interface AdcConfigure<const msp430adc12_channel_config_t*>; */
  //uses interface LinkEstimator;
  uses interface Read<uint16_t> as ReadSensor;
}
implementation {
  message_t packet;
  bool sendBusy = FALSE, CongStatus;
  
  /* uint16_t seqno = 0; */
  /* uint16_t buffer[3]; */
  bool msg_missed = FALSE;
  bool route_found  = FALSE;
  /* float x1_p; */
  /* float x2_p; */
  
  /* ECollMessage* datapkt;  */
  ECollMessage* sensordata;
  bool StartSense = FALSE;
  /* bool NetEst = FALSE; */
  
  void printfFloat(float toBePrinted); 
  
  /* const msp430adc12_channel_config_t config = { */
  /*   INPUT_CHANNEL_A5, REFERENCE_VREFplus_AVss, REFVOLT_LEVEL_2_5, */
  /*   SHT_SOURCE_SMCLK, SHT_CLOCK_DIV_1, SAMPLE_HOLD_64_CYCLES, */
  /*   SAMPCON_SOURCE_SMCLK, SAMPCON_CLOCK_DIV_1 */
  /* }; */
  
  event void Boot.booted() {
    /* atomic x1_p = 0; */
    /* atomic x2_p = 0; */
    StartSense = FALSE;
    call RadioControl.start();
    call UserButton.enable();
  }
  
  event void RadioControl.startDone(error_t err) {
    if (err != SUCCESS){
      call RadioControl.start();
    }
    else {
      /* call Resource.request(); */
      
      call RoutingControl.start();
      
      if (TOS_NODE_ID == COORDINATOR_ADDRESS) { 
	call RootControl.setRoot();
	//printf("This is root \n"); 
	//printfflush();
      }
      //else  { call Timer.startPeriodic(1000); }
    }    
  }
  
  event void RadioControl.stopDone(error_t err) {}
  
  void sendMessage() {  	
    if (call Send.send(&packet, sizeof(ECollMessage)) != SUCCESS) {
      //call Leds.led1Toggle();
      /* call Leds.led1Off(); */
    }
    else {
      sendBusy = TRUE;
      call Leds.led2Toggle();
    }
    /* seqno++; */
  }

  event void ReadSensor.readDone(error_t result, uint16_t data)
  {
    if(result == SUCCESS){
      sensordata = (ECollMessage*)call Send.getPayload(&packet, sizeof(ECollMessage));
      atomic{
	sensordata->seqno = data;
	call Leds.led0Off();
      }
    }else{
      call Leds.led0Toggle();
      /* call Leds.led1Off(); */
    }
  }

  async event void Capisrunning.Caphasstarted(uint32_t t0 , uint32_t dt){ 
    /* call MultiChannel.getData(); */
    /* if(!NetEst){ */
    /*   printf("Network is established\n"); */
    /*   printfflush(); */
    /*   NetEst = TRUE; */
    /* } */
    if(StartSense)
      call ReadSensor.read();
  }
  
  async event void Capisrunning.Caphasfinished(){
    if (route_found == TRUE ){
      //printf("AppLayer Data sent \n");
      //printfflush();
      if(StartSense){
	sendMessage();
	msg_missed = FALSE;
	/* call Leds.led2Toggle(); */
      }
    }else{
      /* call Leds.led2Off(); */
    }
  }

  async event void Capisrunning.MyTShasStarted(){ }
  
  event void Send.sendDone(message_t* m, error_t err) {	
    sendBusy = FALSE;
    route_found = TRUE;
    /* if (err == SUCCESS) {call Leds.led2Toggle();} */
    /* else {call Leds.led2Off();} */
    /* if (err != SUCCESS) {call Leds.led0Toggle();} */
    /* else {call Leds.led0Off();} */
  }

  /* async event void MultiChannel.dataReady(uint16_t *buf, uint16_t numSamples) */
  /* { */
  /*   // Copy sensor readings */
  /*   datapkt = (ECollMessage*)call Send.getPayload(&packet, sizeof(ECollMessage)); */
  /*   atomic{	 */
  /*     datapkt->seqno = seqno; */
  /*     datapkt->data[0] = buf[1]; //buf[1]  data[0] Lower tank */
  /*     datapkt->data[1] = buf[2];  //buf[2] data[1] Upper Tank tank */
  /*   } */
  /* } */

  //when readtemp request has been processed
  /* async command const msp430adc12_channel_config_t* AdcConfigure.getConfiguration() */
  /* { */
  /*   return &config; */
  /* } */
  
  /***** Finish Reading Data from Sensors **************/
  /*********************************************************************
   *                            Resource
   **********************************************************************/
  /* event void Resource.granted() */
  /* { */
  /*   atomic { */
  /*     adc12memctl_t memctl[] = { {INPUT_CHANNEL_A0, REFERENCE_VREFplus_AVss}, {INPUT_CHANNEL_A1, REFERENCE_VREFplus_AVss}}; */
      
  /*     if (call MultiChannel.configure(&config, memctl, 2, buffer, 3, 0) != SUCCESS) { */
  /* 	//call Leds.led0On(); */
  /*     } */
  /*   } */
  /* } */

  event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
    return msg;
  }
  
  /*********************************************************************
   * 7) User Button
   *********************************************************************/
  event void UserButton.notify( button_state_t state ) {	
    if ( state == BUTTON_PRESSED ) {      
    } else if ( state == BUTTON_RELEASED ) {
      /* call RadioControl.start(); */
      atomic{
	StartSense = TRUE;
      }
    }
  }
}  // Implementation ends

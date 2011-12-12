#include "OpenWSN.h"
#include "ICMPv6.h"

module ICMPv6EchoP {
   provides interface Init as SoftwareInit;
   //down the stack
   uses interface OpenSend as OpenSendToLower[uint8_t iana_number];
   //up the stack
   provides interface OpenReceive as OpenReceiveFromLower[uint8_t iana_number];
   //misc
   uses interface PacketFunctions;
   uses interface Malloc;
   uses interface IDManager;
   uses interface OpenSerial;
   provides interface Trigger as TriggerICMPv6Echo;
   provides interface DebugPrint;
}

implementation {
   /*-------------------------------- variables -----------------------------------------*/

   bool        busySending;
   open_addr_t hisAddress;
   uint16_t    icmpv6_seq=0;

   /*-------------------------------- prototypes ----------------------------------------*/

   task void taskPrintDebug();
   task void taskSendEchoRequest();

   /*-------------------------------- helper functions ----------------------------------*/

   task void taskPrintDebug() {
      //TBC
   }

   /*-------------------------------- interfaces ----------------------------------------*/

   //SoftwareInit
   command error_t SoftwareInit.init() {
      busySending = FALSE;
      return SUCCESS;
   }

   //TriggerICMPv6Echo
   command void TriggerICMPv6Echo.trigger() {
      uint8_t number_bytes_from_input_buffer;
      uint8_t input_buffer[16];
      //get command from OpenSerial (16B IPv6 destination address)
      number_bytes_from_input_buffer = call OpenSerial.getInputBuffer(&(input_buffer[0]),sizeof(input_buffer));
      if (number_bytes_from_input_buffer!=sizeof(input_buffer)) {
         call OpenSerial.printError(COMPONENT_ICMPv6ECHO,ERR_INPUTBUFFER_LENGTH,
               (errorparameter_t)number_bytes_from_input_buffer,
               (errorparameter_t)0);
         return;
      };
      hisAddress.type  = ADDR_128B;
      memcpy(&(hisAddress.addr_128b[0]),&(input_buffer[0]),16);
      //send
      if (busySending==TRUE) {
         call OpenSerial.printError(COMPONENT_ICMPv6ECHO,ERR_BUSY_SENDING,0,0);
      } else {
         busySending = TRUE;
         post taskSendEchoRequest();
      }
   }
   task void taskSendEchoRequest() {
      OpenQueueEntry_t* msg;
      msg = call Malloc.getFreePacketBuffer();
      if (msg==NULL) {
         call OpenSerial.printError(COMPONENT_ICMPv6ECHO,ERR_NO_FREE_PACKET_BUFFER,(errorparameter_t)0,(errorparameter_t)0);
         return;
      }
      //admin
      msg->creator                               = COMPONENT_ICMPv6ECHO;
      msg->owner                                 = COMPONENT_ICMPv6ECHO;
      //l4
      msg->l4_protocol                           = IANA_ICMPv6;
      msg->l4_sourcePortORicmpv6Type             = IANA_ICMPv6_ECHO_REQUEST;
      //l3
      memcpy(&(msg->l3_destinationORsource),&hisAddress,sizeof(open_addr_t));
      //payload
      call PacketFunctions.reserveHeaderSize(msg,4);
      call PacketFunctions.htonl(0x789abcde,(uint8_t*)(msg->payload));
      //ICMPv6 header
      call PacketFunctions.reserveHeaderSize(msg,sizeof(ICMPv6_ht));
      ((ICMPv6_ht*)(msg->payload))->type         = msg->l4_sourcePortORicmpv6Type;
      ((ICMPv6_ht*)(msg->payload))->code         = 0;
      call PacketFunctions.htons(0x1234       ,(uint8_t*)&((ICMPv6_ht*)(msg->payload))->identifier);
      call PacketFunctions.htons(icmpv6_seq++ ,(uint8_t*)&((ICMPv6_ht*)(msg->payload))->sequence_number); 
      call PacketFunctions.calculateChecksum(msg,(uint8_t*)&(((ICMPv6_ht*)(msg->payload))->checksum));//call last
      //send
      if (call OpenSendToLower.send[msg->l4_sourcePortORicmpv6Type](msg)!=SUCCESS) {
         busySending = FALSE;
         call Malloc.freePacketBuffer(msg);
      }
   }

   //OpenSendToLower
   event void OpenSendToLower.sendDone[uint8_t iana_number](OpenQueueEntry_t* msg, error_t error) {
      msg->owner = COMPONENT_ICMPv6ECHO;
      if (msg->creator!=COMPONENT_ICMPv6ECHO) {//that was a packet I had not created
         call OpenSerial.printError(COMPONENT_ICMPv6ECHO,ERR_SENDDONE_FOR_MSG_I_DID_NOT_SEND,0,0);
      }
      call Malloc.freePacketBuffer(msg);
      busySending = FALSE;
   }

   //DebugPrint
   command void DebugPrint.print() {
      post taskPrintDebug();
   }

   //OpenReceiveFromLower
   command void OpenReceiveFromLower.receive[uint8_t icmpv6_type](OpenQueueEntry_t* msg) {
      msg->owner = COMPONENT_ICMPv6ECHO;
      switch(icmpv6_type) {
         case IANA_ICMPv6_ECHO_REQUEST:
            call OpenSerial.printError(COMPONENT_ICMPv6ECHO,ERR_RCVD_ECHO_REQUEST,(errorparameter_t)0,(errorparameter_t)0);
            //reply with same OpenQueueEntry_t
            msg->creator                         = COMPONENT_ICMPv6ECHO;
            msg->l4_sourcePortORicmpv6Type       = IANA_ICMPv6_ECHO_REPLY;
            ((ICMPv6_ht*)(msg->payload))->type   = msg->l4_sourcePortORicmpv6Type;
            call PacketFunctions.calculateChecksum(msg,(uint8_t*)&(((ICMPv6_ht*)(msg->payload))->checksum));//call last
            busySending = TRUE;
            if (call OpenSendToLower.send[msg->l4_sourcePortORicmpv6Type](msg)!=SUCCESS) {
               busySending = FALSE;
               call Malloc.freePacketBuffer(msg);
            }
            break;
         case IANA_ICMPv6_ECHO_REPLY:
            call OpenSerial.printError(COMPONENT_ICMPv6ECHO,ERR_RCVD_ECHO_REPLY,(errorparameter_t)0,(errorparameter_t)0);
            call Malloc.freePacketBuffer(msg);
            break;
         default:
            call OpenSerial.printError(COMPONENT_ICMPv6ECHO,ERR_UNSUPPORTED_ICMPV6_TYPE,
                  (errorparameter_t)icmpv6_type,
                  (errorparameter_t)0);
            call Malloc.freePacketBuffer(msg);
            break;
      }
   }

   /*-------------------------------- defaults ------------------------------------------*/

   default command error_t OpenSendToLower.send[uint8_t icmpv6_type](OpenQueueEntry_t* msg) {
      call OpenSerial.printError(COMPONENT_ICMPv6ECHO,ERR_UNSUPPORTED_ICMPV6_TYPE,
            (errorparameter_t)icmpv6_type,
            (errorparameter_t)1);
      return FAIL;
   }
}

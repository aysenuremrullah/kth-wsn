//#include <message.h> //needed for declaration of message_t
//#include "LATIN.h"

interface RadioReceive {
   ////////event void receive(OpenQueueEntry_t* msg);
   event void receive(uint8_t* msg);
}

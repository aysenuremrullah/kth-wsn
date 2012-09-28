/*
 * Copyright (c) 2012, KTH Royal Institute of Technology
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 *  - Redistributions of source code must retain the above copyright notice, this list
 * 	  of conditions and the following disclaimer.
 *
 * 	- Redistributions in binary form must reproduce the above copyright notice, this
 *    list of conditions and the following disclaimer in the documentation and/or other
 *	  materials provided with the distribution.
 *
 * 	- Neither the name of the KTH Royal Institute of Technology nor the names of its
 *    contributors may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,
 * OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY
 * OF SUCH DAMAGE.
 *
 */
/**
 * @author Anser Ahmed<ansera@kth.se>
 * @modified 2012/04/13
 */

#include "app_profile.h"
configuration CoordinatorAppC
{
} implementation {
  components MainC, LedsC, Ieee802154BeaconEnabledC as MAC,
			  new TimerMilliC() as Timer;

  components CoordinatorC as App;
  components UserButtonC;
  App.UserButton -> UserButtonC;
  
  App.MLME_START -> MAC;
  App.MCPS_DATA -> MAC;
  App.Frame -> MAC;

  MainC.Boot <- App;
  App.Leds -> LedsC;
  App.MLME_RESET -> MAC;
  App.MLME_SET -> MAC;
  App.MLME_GET -> MAC;
  App.MLME_GTS -> MAC;

  App.SendTimer -> Timer;
  App.Packet -> MAC;

  App.IEEE154TxBeaconPayload -> MAC;
  
  MAC.SubGtsSpecUpdated -> App.GtsSpecUpdated;
  App.GtsUtility -> MAC;
  App.SetGtsCoordinatorDb -> MAC;
  App.IsEndSuperframe -> MAC;
  
  components PrintfC;
  components SerialStartC;
  components SerialActiveMessageC as Serial;
  
  App.SerialControl -> Serial;
  App.UartSend -> Serial.AMSend[AM_MYMSG];
  App.UartReceive -> Serial.Receive[AM_ACTUATORMSG];
  App.UartAMPacket -> Serial;

}

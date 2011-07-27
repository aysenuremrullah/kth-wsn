/*
 * Copyright (c) 2010, KTH Royal Institute of Technology
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
 * @author Aitor Hernandez <aitorhh@kth.se>
 * @author Joao Faria <jfff@kth.se>
 * 
 * @version  $Revision: 1.0 Date: 2010/11/03 $ 
 * @modified 2011/02/01 
 */
#define NEW_PRINTF_SEMANTICS

configuration ControllerAppC {
}
implementation {

	components MainC, ControllerC, LedsC, SerialActiveMessageC as Serial;

	ControllerC.Boot -> MainC;
	ControllerC.Leds -> LedsC;

	/****************************************
	 * 802.15.4
	 *****************************************/
	components Ieee802154BeaconEnabledC as MAC;
	ControllerC.IEEE154TxBeaconPayload -> MAC;
	components new Alarm62500hz32VirtualizedC() as SlotAlarm,
	new Alarm62500hz32VirtualizedC() as EndCapPeriod;

	ControllerC.SlotAlarm -> SlotAlarm;
	ControllerC.EndCapPeriod -> EndCapPeriod;

	ControllerC.MLME_RESET -> MAC;
	ControllerC.MLME_SET -> MAC;
	ControllerC.MLME_GET -> MAC;

	ControllerC.MLME_START -> MAC;
	ControllerC.MCPS_DATA -> MAC;
	ControllerC.Frame -> MAC;
	ControllerC.Packet -> MAC;

	components UserButtonC;
	ControllerC.UserButton -> UserButtonC;

	ControllerC.SerialControl -> Serial;
	ControllerC.UartSend -> Serial.AMSend[AM_SENSORMATRIXMSG];
	ControllerC.UartReceive -> Serial.Receive[AM_ACTUATIONMATRIXMSG];
	ControllerC.UartAMPacket -> Serial;

	/****************************************
	 * Printf
	 *****************************************/
	components PrintfC;
	components SerialStartC;
}

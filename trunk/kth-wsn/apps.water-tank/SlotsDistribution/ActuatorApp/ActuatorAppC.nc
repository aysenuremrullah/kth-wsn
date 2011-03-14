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

configuration ActuatorAppC {
}
implementation {

	components MainC, ActuatorC, LedsC;
	ActuatorC.Boot -> MainC;
	ActuatorC.Leds -> LedsC;

	/****************************************
	 * 802.15.4
	 *****************************************/

	components Ieee802154BeaconEnabledC as MAC;
	ActuatorC.MLME_SCAN -> MAC;
	ActuatorC.MLME_SYNC -> MAC;
	ActuatorC.MLME_BEACON_NOTIFY -> MAC;
	ActuatorC.MLME_SYNC_LOSS -> MAC;
	ActuatorC.BeaconFrame -> MAC;


	ActuatorC.MLME_RESET -> MAC;
	ActuatorC.MLME_SET -> MAC;
	ActuatorC.MLME_GET -> MAC;

	ActuatorC.MLME_START -> MAC;
	ActuatorC.MCPS_DATA -> MAC;
	ActuatorC.Frame -> MAC;
	ActuatorC.Packet -> MAC;

	components HplMsp430GeneralIOC;
	components new Msp430GpioC() as ADC0;
	ADC0 -> HplMsp430GeneralIOC.Port60;
	ActuatorC.ADC0 -> ADC0;

	components new Msp430GpioC() as ADC1;
	ADC1 -> HplMsp430GeneralIOC.Port61;
	ActuatorC.ADC1 -> ADC1;
}


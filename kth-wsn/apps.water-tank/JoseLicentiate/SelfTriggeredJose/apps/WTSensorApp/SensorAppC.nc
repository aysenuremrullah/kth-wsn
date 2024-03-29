/*
 * Copyright (c) 2011, KTH Royal Institute of Technology
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
 * @author Joao Faria <jfff@kth.se>
 * @author Aitor Hernandez <aitorhh@kth.se>
 * 
 * @version  $Revision: 1.2 Date: 2011/04/21 $ 
 */

#include "Msp430Adc12.h"
#include <Timer.h>
#include "printf.h"

configuration SensorAppC {
}
implementation
{
	//components implemented
	components MainC,
	LedsC,
	HplMsp430GeneralIOC;

	components SensorC,
	new Msp430Adc12ClientAutoRVGC() as AutoAdc, Ieee802154BeaconEnabledC as MAC;
	
	
	
	
	//components HplUserButtonC0,
	//           HplUserButtonC1;

	//connections
	//SensorC.Relay0->HplUserButtonC0.GeneralIO;
	//SensorC.Relay1->HplUserButtonC1.GeneralIO;
	SensorC -> MainC.Boot;
	SensorC.Leds -> LedsC;
	SensorC.Resource -> AutoAdc;
	AutoAdc.AdcConfigure -> SensorC;

	SensorC.MultiChannel -> AutoAdc.Msp430Adc12MultiChannel;

	SensorC.MLME_SCAN -> MAC;
	SensorC.MLME_SYNC -> MAC;
	SensorC.MLME_BEACON_NOTIFY -> MAC;
	SensorC.MLME_SYNC_LOSS -> MAC;
	SensorC.MCPS_DATA -> MAC;
	SensorC.MLME_GTS -> MAC;
	SensorC.Frame -> MAC;
	SensorC.BeaconFrame -> MAC;
	SensorC.GtsUtility -> MAC;
	SensorC.Packet -> MAC;

	SensorC.MLME_RESET -> MAC;
	SensorC.MLME_SET -> MAC;
	SensorC.MLME_GET -> MAC;

	SensorC.IsGtsOngoing -> MAC.IsGtsOngoing;

	components LocalTime62500hzC;
	SensorC.LocalTime -> LocalTime62500hzC;
	
	
	SensorC.IsEndSuperframe -> MAC;
	
	components PrintfC;
	components SerialStartC;
}

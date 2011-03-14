/*
 * EncLS7366RAppC.nc
 * 
 * KTH | Royal Institute of Technology
 * Automatic Control
 *
 *           Project: se.kth.tinyos2x.ieee802154.tkn154
 *        Created on: 2010/05/10 
 * Last modification: 
 *            Author: aziz
 *     
 */

configuration EncLS7366RAppC{
}
implementation {

	components MainC, EncLS7366RC, LedsC, new TimerMilliC() as TimerCalc;
	EncLS7366RC.Boot -> MainC;
	EncLS7366RC.Leds -> LedsC;
	
	EncLS7366RC.TimerCalc -> TimerCalc;
		
	/****************************************
	* 802.15.4
	*****************************************/
#ifdef TKN154_BEACON_DISABLED
	components Ieee802154NonBeaconEnabledC as MAC;
#else
	components Ieee802154BeaconEnabledC as MAC;
	EncLS7366RC.MLME_SCAN -> MAC;
	EncLS7366RC.MLME_SYNC -> MAC;
	EncLS7366RC.MLME_BEACON_NOTIFY -> MAC;
	EncLS7366RC.MLME_SYNC_LOSS -> MAC;
	EncLS7366RC.BeaconFrame -> MAC;
	
	components RandomC;
	EncLS7366RC.Random -> RandomC;


#endif
	
	EncLS7366RC.MLME_RESET -> MAC;
	EncLS7366RC.MLME_SET -> MAC;
	EncLS7366RC.MLME_GET -> MAC;
	  
	EncLS7366RC.MLME_START -> MAC;
	EncLS7366RC.MCPS_DATA -> MAC;
	EncLS7366RC.Frame -> MAC;
	EncLS7366RC.Packet -> MAC;
	
}


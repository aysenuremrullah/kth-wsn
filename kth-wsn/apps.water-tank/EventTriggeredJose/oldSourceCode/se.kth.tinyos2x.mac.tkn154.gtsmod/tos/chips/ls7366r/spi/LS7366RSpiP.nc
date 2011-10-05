/*
 * LS7366RSpiP.nc
 * 
 * KTH | Royal Institute of Technology
 * Automatic Control
 *
 * 		  	 Project: se.kth.tinyos2x.mac.tkn154
 *  	  Created on: 2010/06/02  
 * Last modification:  
 *     		  Author: Aitor Hernandez <aitorhh@kth.se>
 *     
 */

module LS7366RSpiP @safe() {

  provides {
    interface ChipSpiResource;
    interface Resource[ uint8_t id ];
    interface LS7366RRegister as Reg[ uint8_t id ];
    interface LS7366RStrobe as Strobe[ uint8_t id ];
  }
  
  uses {
    interface Resource as SpiResource;
    interface SpiByte;
    
    interface State as WorkingState;
    interface Leds;
  }
}

implementation {

  enum {
    RESOURCE_COUNT = uniqueCount( "LS7366RSpi.Resource" ),
    NO_HOLDER = 0xFF,
  };

  /** WorkingStates */
  enum {
    S_IDLE,
    S_BUSY,
  };

  /** Address to read/write on the LS7366R, also maintains caller's client id */
  norace uint16_t m_addr;
  
  /** Each bit represents a client ID that is requesting SPI bus access */
  uint8_t m_requests = 0;
  
  /** The current client that owns the SPI bus */
  uint8_t m_holder = NO_HOLDER;
  
  /** TRUE if it is safe to release the SPI bus after all users say ok */
  bool release;
  
  /***************** Prototypes ****************/
  error_t attemptRelease();
  task void grant();
  
  /***************** ChipSpiResource Commands ****************/
  /**
   * Abort the release of the SPI bus.  This must be called only with the
   * releasing() event
   */
  async command void ChipSpiResource.abortRelease() {
    atomic release = FALSE;
  }
  
  /**
   * Release the SPI bus if there are no objections
   */
  async command error_t ChipSpiResource.attemptRelease() {
    return attemptRelease();
  }
  
  /***************** Resource Commands *****************/
  async command error_t Resource.request[ uint8_t id ]() {
        
    atomic {
      if ( call WorkingState.requestState(S_BUSY) == SUCCESS ) {
        m_holder = id;
        if(call SpiResource.isOwner()) {
          post grant();
          
        } else {
          call SpiResource.request();
        }
        
      } else {
        m_requests |= 1 << id;
      }
    }
    return SUCCESS;
  }
  
  async command error_t Resource.immediateRequest[ uint8_t id ]() {
    error_t error;
        
    atomic {
      if ( call WorkingState.requestState(S_BUSY) != SUCCESS ) {
        return EBUSY;
      }
      
      
      if(call SpiResource.isOwner()) {
        m_holder = id;
        error = SUCCESS;
      
      } else if ((error = call SpiResource.immediateRequest()) == SUCCESS ) {
        m_holder = id;
        
      } else {
        call WorkingState.toIdle();
      }
    }
    return error;
  }

  async command error_t Resource.release[ uint8_t id ]() {
    uint8_t i;
    atomic {
      if ( m_holder != id ) {
        return FAIL;
      }

      m_holder = NO_HOLDER;
      if ( !m_requests ) {
        call WorkingState.toIdle();
        attemptRelease();
        
      } else {
        for ( i = m_holder + 1; ; i++ ) {
          i %= RESOURCE_COUNT;
          
          if ( m_requests & ( 1 << i ) ) {
            m_holder = i;
            m_requests &= ~( 1 << i );
            post grant();
            return SUCCESS;
          }
        }
      }
    }
    
    return SUCCESS;
  }
  
  async command uint8_t Resource.isOwner[ uint8_t id ]() {
    atomic return (m_holder == id);
  }

  /***************** SpiResource Events ****************/
  event void SpiResource.granted() {
    post grant();
  }
  /***************** Strobe Commands ****************/
  async command error_t Strobe.strobe[ uint8_t addr ]() {
      atomic {
        if(call WorkingState.isIdle()) {
          return EBUSY;
        }
      }
      call SpiByte.write( addr );
      
      return SUCCESS;
    }

  /***************** Register Commands ****************/
  async command error_t Reg.read[ uint8_t addr ]( uint8_t* data , uint8_t length) {
    	
	 uint8_t i = 0;
    atomic {
      if(call WorkingState.isIdle()) {
        return EBUSY;
      }
    }
    
    call SpiByte.write( addr | LS7366R_OP_RD);
    for ( i = 0 ; i < length ; i++) data[i] = call SpiByte.write( 0 );

    return SUCCESS;

  }

  async command error_t Reg.readByte[ uint8_t addr ]( uint8_t* data) {

      atomic {
        if(call WorkingState.isIdle()) {
          return EBUSY;
        }
      }

      call SpiByte.write(addr | LS7366R_OP_RD );
      *data = call SpiByte.write( 0x55 );

      
      return SUCCESS;
    }
    async command error_t Reg.readWord[ uint8_t addr ]( uint16_t* data) {

       atomic {
         if(call WorkingState.isIdle()) {
           return EBUSY;
         }
       }

       call SpiByte.write(addr | LS7366R_OP_RD );
       
       *data = call SpiByte.write( 0x55 );
       *(data+1) = call SpiByte.write( 0x55 );

       
       return SUCCESS;
     }
  async command error_t Reg.writeByte[ uint8_t addr ]( uint8_t data) {

    atomic {
      if(call WorkingState.isIdle()) {
        return EBUSY;
      }
    }

    call SpiByte.write(addr | LS7366R_OP_WR );
    call SpiByte.write( data );

    
    return SUCCESS;
  }
  async command error_t Reg.writeWord[ uint8_t addr ]( uint16_t data) {

     atomic {
       if(call WorkingState.isIdle()) {
         return EBUSY;
       }
     }

     call SpiByte.write(addr | LS7366R_OP_WR );
     
     call SpiByte.write( data >> 8 );
     call SpiByte.write( data & 0xFF );

     
     return SUCCESS;
   }
  
  /***************** Functions ****************/
  error_t attemptRelease() {
    if(m_requests > 0 
        || m_holder != NO_HOLDER 
        || !call WorkingState.isIdle()) {
      return FAIL;
    }
    
    atomic release = TRUE;
    signal ChipSpiResource.releasing();
    atomic {
      if(release) {
        call SpiResource.release();
        return SUCCESS;
      }
    }
    
    return EBUSY;
  }
  
  task void grant() {
    uint8_t holder;
    atomic { 
      holder = m_holder;
    }
    signal Resource.granted[ holder ]();
  }

  /***************** Defaults ****************/
  default event void Resource.granted[ uint8_t id ]() {}

  default async event void ChipSpiResource.releasing() {}
  
}

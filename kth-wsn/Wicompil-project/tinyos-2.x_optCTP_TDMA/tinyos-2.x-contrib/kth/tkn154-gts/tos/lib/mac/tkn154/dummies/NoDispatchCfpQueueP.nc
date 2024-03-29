/*
 * Copyright (c) 2010, KTH Royal Institute of Technology
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without 
 * modification, are permitted provided that the following conditions 
 * are met:
 * - Redistributions of source code must retain the above copyright notice,
 *   this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright 
 *   notice, this list of conditions and the following disclaimer in the 
 *   documentation and/or other materials provided with the distribution.
 * - Neither the name of the KTH Royal Institute of Technology nor the names 
 *   of its contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS 
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT 
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT 
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, 
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED 
 * TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, 
 * OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY 
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT 
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE 
 * USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */
/** Empty placeholder component for DispatchQueueP.
 *
 * @author Aitor Hernandez <aitorhh@kth.se>
 * @version  $Revision: 1.0 Date: 2010/06/05 $
 * @modified 2010/06/16
 */

#include "TKN154_MAC.h"
generic module NoDispatchCfpQueueP() {
  provides
  {
    interface Init as Reset;
    interface FrameTx[uint8_t client];
    interface Purge;
  } uses {
    interface Queue<ieee154_txframe_t*>;
    interface FrameTx as CfpTx;
  }
}
implementation
{
  command error_t Reset.init() { return SUCCESS; }

  command ieee154_status_t FrameTx.transmit[uint8_t client](ieee154_txframe_t *txFrame)
  {
    return IEEE154_TRANSACTION_OVERFLOW;
  }

  event void CfpTx.transmitDone(ieee154_txframe_t *txFrame, ieee154_status_t status) { }

  default event void FrameTx.transmitDone[uint8_t client](ieee154_txframe_t *txFrame, ieee154_status_t status){}

  command ieee154_status_t Purge.purge(uint8_t msduHandle)
  {
    return IEEE154_INVALID_HANDLE;
  }
  
  default event void Purge.purgeDone(ieee154_txframe_t *txFrame, ieee154_status_t status){}
}

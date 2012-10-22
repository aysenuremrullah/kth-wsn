#include <DisseminationEngine.h>
#include "printf.h"
/*
 * Copyright (c) 2006 Arch Rock Corporation
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * - Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the
 *   distribution.
 * - Neither the name of the Arch Rock Corporation nor the names of
 *   its contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE
 * ARCHED ROCK OR ITS CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE
 *
 */

/**
 * The DisseminatorC component holds and synchronizes a single value
 * of a chosen type, and identifies that value by a chosen 16-bit key.
 * Different nodes should use the same key for the same value.
 *
 * See TEP118 - Dissemination for details.
 * 
 * @param t the type of the object that will be disseminated
 * @param key the 16-bit identifier of the disseminated object
 *
 * @author Gilman Tolle <gtolle@archrock.com>
 * @version $Revision: 1.1 $ $Date: 2007-09-14 00:22:18 $
 */

generic configuration DisseminatorC(typedef t, uint16_t key) {
  provides interface DisseminationValue<t>;
  provides interface DisseminationUpdate<t>;
}
implementation {
  enum {
    TIMER_ID = unique("DisseminationTimerC.TrickleTimer")
  };

  components new DisseminatorP(t);
  DisseminationValue = DisseminatorP;
  DisseminationUpdate = DisseminatorP;

  components DisseminationEngineP;
  DisseminationEngineP.DisseminationCache[key] -> DisseminatorP;
  DisseminationEngineP.DisseminatorControl[TIMER_ID] -> DisseminatorP;

  components DisseminationTimerP;
  DisseminationEngineP.TrickleTimer[key] -> 
    DisseminationTimerP.TrickleTimer[TIMER_ID];

  components LedsC;
  DisseminatorP.Leds -> LedsC;
}

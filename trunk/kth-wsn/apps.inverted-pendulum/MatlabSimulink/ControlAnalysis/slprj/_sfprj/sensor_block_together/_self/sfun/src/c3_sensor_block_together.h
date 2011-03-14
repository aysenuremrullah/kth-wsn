#ifndef __c3_sensor_block_together_h__
#define __c3_sensor_block_together_h__

/* Include files */
#include "sfc_sf.h"
#include "sfc_mex.h"
#include "rtwtypes.h"

/* Type Definitions */
typedef struct {
  char *context;
  char *name;
  char *dominantType;
  char *resolved;
  uint32_T fileLength;
  uint32_T fileTime1;
  uint32_T fileTime2;
} c3_ResolvedFunctionInfo;

typedef struct {
  real_T c3_actuator_delay_p;
  real_T c3_actuator_value_p;
  real_T c3_theta_delay_p;
  real_T c3_theta_value_p;
  real_T c3_xc_delay_p;
  real_T c3_xc_value_p;
  SimStruct *S;
  uint32_T chartNumber;
  uint32_T instanceNumber;
  boolean_T c3_actuator_delay_p_not_empty;
  boolean_T c3_actuator_value_p_not_empty;
  boolean_T c3_doneDoubleBufferReInit;
  boolean_T c3_isStable;
  boolean_T c3_theta_delay_p_not_empty;
  boolean_T c3_theta_value_p_not_empty;
  boolean_T c3_xc_delay_p_not_empty;
  boolean_T c3_xc_value_p_not_empty;
  uint8_T c3_is_active_c3_sensor_block_together;
  ChartInfoStruct chartInfo;
} SFc3_sensor_block_togetherInstanceStruct;

/* Named Constants */

/* Variable Declarations */

/* Variable Definitions */

/* Function Declarations */
extern const mxArray
  *sf_c3_sensor_block_together_get_eml_resolved_functions_info(void);

/* Function Definitions */
extern void sf_c3_sensor_block_together_get_check_sum(mxArray *plhs[]);
extern void c3_sensor_block_together_method_dispatcher(SimStruct *S, int_T
  method, void *data);

#endif

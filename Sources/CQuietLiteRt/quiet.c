#define _GNU_SOURCE
#include "CQuietLiteRt.h"

#include <dlfcn.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// LiteRT exports no logger setter, but the log level an environment is created with
// holds for the process, including the environments core creates later. These types
// mirror LiteRtAny and LiteRtEnvOption, which LiteRT keeps ABI stable.

typedef struct {
  int type;
  union {
    bool bool_value;
    int64_t int_value;
    double real_value;
    const char *str_value;
    const void *ptr_value;
  };
} Any;

typedef struct {
  int tag;
  Any value;
} EnvOption;

typedef int (*CreateEnvironment)(int, const EnvOption *, void **);

enum { kTagMinLoggerSeverity = 25, kAnyTypeInt = 2, kSeverityError = 3 };

void desertant_quiet_litert(void) {
  CreateEnvironment create = (CreateEnvironment)dlsym(RTLD_DEFAULT, "LiteRtCreateEnvironment");
  if (!create) return;
  // Kept for the life of the process, like core's own environment.
  static void *environment = NULL;
  const EnvOption option = {kTagMinLoggerSeverity, {.type = kAnyTypeInt, .int_value = kSeverityError}};
  create(1, &option, &environment);
}

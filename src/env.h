
#ifndef LOCO_ENV_H
#define LOCO_ENV_H
#include "value.h"
typedef struct EnvBinding { char *name; LogoVal *value; struct EnvBinding *next; } EnvBinding;
typedef struct EnvFrame { EnvBinding *bindings; struct EnvFrame *parent; } EnvFrame;
typedef struct { EnvFrame *top; EnvFrame *global; } Env;
void env_init(Env *e);
void env_free(Env *e);
EnvFrame *env_push_frame(Env *e);
void env_pop_frame(Env *e);
void env_make(Env *e, const char *name, LogoVal *val);
void env_set_global(Env *e, const char *name, LogoVal *val);
LogoVal *env_thing(Env *e, const char *name);
void env_local(Env *e, const char *name);
int env_is_bound(Env *e, const char *name);
char **env_list_names(Env *e, int global_only, int *count);
#endif


#ifndef LOCO_GC_H
#define LOCO_GC_H
#include "value.h"
extern LogoVal *gc_all_values;
extern int gc_count;
extern int gc_threshold;
LogoVal *gc_alloc(void);
void gc_push_root(LogoVal **root);
void gc_pop_root(void);
void gc_collect(void);
void gc_mark(LogoVal *v);
#endif

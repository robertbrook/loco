
#ifndef LOCO_WORKSPACE_H
#define LOCO_WORKSPACE_H
#include "value.h"
struct Interp;
typedef enum { PROC_USER, PROC_PRIMITIVE, PROC_MACRO } ProcType;
typedef struct { char *name; int type; char *default_expr; } InputSpec;
typedef struct Proc {
    char *name;
    ProcType ptype;
    int min_inputs, default_inputs, max_inputs;
    InputSpec *inputs;
    int n_inputs;
    char **body_lines;
    int n_body_lines;
    LogoVal *(*fn)(struct Interp *interp, LogoVal **args, int nargs);
    int buried, traced, stepped;
} Proc;
typedef struct PProp { char *propname; LogoVal *value; struct PProp *next; } PProp;
typedef struct PList { char *name; PProp *props; struct PList *next; } PList;
typedef struct { Proc **procs; int count, capacity; PList *plists; } Workspace;
void ws_init(Workspace *ws);
void ws_free(Workspace *ws);
Proc *ws_lookup(Workspace *ws, const char *name);
void ws_define(Workspace *ws, Proc *proc);
void ws_erase(Workspace *ws, const char *name);
int ws_is_primitive(Workspace *ws, const char *name);
int ws_is_defined(Workspace *ws, const char *name);
char **ws_list_all(Workspace *ws, int include_buried, int *count);
char **ws_list_user(Workspace *ws, int include_buried, int *count);
char **ws_list_primitives(Workspace *ws, int include_buried, int *count);
void ws_pprop(Workspace *ws, const char *plistname, const char *propname, LogoVal *val);
LogoVal *ws_gprop(Workspace *ws, const char *plistname, const char *propname);
void ws_remprop(Workspace *ws, const char *plistname, const char *propname);
LogoVal *ws_plist(Workspace *ws, const char *plistname);
char **ws_list_plists(Workspace *ws, int *count);
Proc *make_primitive(const char *name, int min, int def, int max,
                     LogoVal *(*fn)(struct Interp *, LogoVal **, int));
#endif

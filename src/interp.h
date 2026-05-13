
#ifndef LOCO_INTERP_H
#define LOCO_INTERP_H
#include <setjmp.h>
#include "value.h"
#include "gc.h"
#include "tokenizer.h"
#include "env.h"
#include "workspace.h"

typedef enum { SIG_NONE, SIG_STOP, SIG_OUTPUT, SIG_THROW, SIG_ERROR, SIG_GOTO, SIG_BYE } SigType;

typedef struct CtrlFrame {
    jmp_buf jmp;
    SigType sig;
    LogoVal *value;
    char tag[512];
    struct CtrlFrame *prev;
} CtrlFrame;

struct OpenFile {
    char name[512];
    FILE *fp;
    char mode[8];
    struct OpenFile *next;
};

typedef struct Interp {
    Workspace ws;
    Env env;
    CtrlFrame *ctrl_stack;
    int *repcount_stack;
    int repcount_top, repcount_cap;
    LogoVal *test_flag;
    LogoVal *last_error;
    char file_prefix[512];
    struct OpenFile *open_files;
    FILE *dribble_fp;
    FILE *read_stream;
    FILE *write_stream;
    char read_stream_name[512];
    char write_stream_name[512];
    int gensym_n;
    int case_ignored;
    LogoVal **tmpl_slots;
    int tmpl_nslots;
    int tmpl_index;
    LogoVal *tmpl_rest;
    LogoVal *continue_value;
    char editor[512];
    int allow_getset;
    int pause_level;
} Interp;

#define CTRL_PUSH(interp, frame) \
    do { (frame).prev = (interp)->ctrl_stack; (frame).sig = SIG_NONE; \
         (frame).value = NULL; (frame).tag[0] = '\0'; \
         (interp)->ctrl_stack = &(frame); } while(0)

#define CTRL_POP(interp) \
    do { if ((interp)->ctrl_stack) (interp)->ctrl_stack = (interp)->ctrl_stack->prev; } while(0)

void interp_init(Interp *interp);
void interp_free(Interp *interp);
int interp_run(Interp *interp, const char *src);
LogoVal *eval_expr(Interp *interp, TokenStream *ts);
void run_stream(Interp *interp, TokenStream *ts);
void run_list(Interp *interp, LogoVal *lst);
LogoVal *eval_template(Interp *interp, LogoVal *tmpl,
                       LogoVal **slots, int nslots, int idx, LogoVal *rest);
LogoVal *apply_proc_by_name(Interp *interp, const char *name,
                             LogoVal **args, int nargs);
LogoVal *apply_proc(Interp *interp, Proc *proc, LogoVal **args, int nargs);
void interp_repl(Interp *interp);
int interp_load_file(Interp *interp, const char *filename);
void interp_stop(Interp *interp);
void interp_output(Interp *interp, LogoVal *val);
void interp_throw(Interp *interp, const char *tag, LogoVal *val);
void interp_error(Interp *interp, const char *fmt, ...);
void interp_goto(Interp *interp, const char *tag);
void interp_push_repcount(Interp *interp, int val);
void interp_pop_repcount(Interp *interp);
int interp_repcount(Interp *interp);
int logo_case_equal(Interp *interp, const char *a, const char *b);
LogoVal *call_named_proc(Interp *interp, const char *name, TokenStream *ts, int in_paren);
void register_all_primitives(Interp *interp);
char *logo_list_to_str(LogoVal *v);
LogoVal *read_list_from_tokens(Interp *interp, TokenStream *ts);
#endif

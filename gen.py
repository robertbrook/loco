import os
BASE = '/home/runner/work/loco/loco'

def write(path, content):
    full = os.path.join(BASE, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, 'w') as f:
        f.write(content)

write('Makefile', '''CC = gcc
CFLAGS = -Wall -Wextra -std=c99 -g -I src -D_POSIX_C_SOURCE=200809L -Wno-unused-parameter
LDFLAGS = -lm

SRCS = src/main.c src/value.c src/gc.c src/tokenizer.c \\
       src/env.c src/workspace.c src/interp.c \\
       src/prim_data.c src/prim_arith.c src/prim_logic.c \\
       src/prim_comm.c src/prim_file.c src/prim_ctrl.c \\
       src/prim_ws.c src/prim_tmpl.c

OBJS = $(SRCS:.c=.o)

loco: $(OBJS)
\t$(CC) $(CFLAGS) -o loco $(OBJS) $(LDFLAGS)

%.o: %.c
\t$(CC) $(CFLAGS) -c $< -o $@

test: test/test_main.c $(filter-out src/main.o, $(OBJS))
\t$(CC) $(CFLAGS) -o test/test_loco test/test_main.c \\
\t    $(filter-out src/main.o, $(OBJS)) $(LDFLAGS)
\t./test/test_loco

clean:
\trm -f $(OBJS) loco test/test_loco

.PHONY: test clean
''')

write('src/value.h', r'''
#ifndef LOCO_VALUE_H
#define LOCO_VALUE_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

typedef enum { LV_WORD, LV_LIST, LV_ARRAY } LogoType;
struct LogoVal;
typedef struct LogoVal LogoVal;

struct LogoVal {
    LogoType type;
    int gc_mark;
    LogoVal *gc_next;
    union {
        struct { char *str; double num; int is_num; } word;
        struct { LogoVal *car; LogoVal *cdr; } list;
        struct { LogoVal **data; int size; int origin; } arr;
    } u;
};

LogoVal *logo_make_word(const char *str);
LogoVal *logo_make_num(double n);
LogoVal *logo_make_int(int n);
LogoVal *logo_cons(LogoVal *car, LogoVal *cdr);
LogoVal *logo_make_array(int size, int origin);
int logo_is_true(LogoVal *v);
int logo_is_false(LogoVal *v);
int logo_is_word(LogoVal *v);
int logo_is_list(LogoVal *v);
int logo_is_array(LogoVal *v);
int logo_is_number(LogoVal *v);
double logo_to_num(LogoVal *v);
int logo_list_length(LogoVal *lst);
LogoVal *logo_list_nth(LogoVal *lst, int n);
LogoVal *logo_list_last(LogoVal *lst);
LogoVal *logo_list_butlast(LogoVal *lst);
LogoVal *logo_build_list(LogoVal **items, int n);
void logo_print_val(LogoVal *v, FILE *out, int show);
char *logo_val_to_str(LogoVal *v);
char *logo_word_str(LogoVal *v);
int logo_equal(LogoVal *a, LogoVal *b, int ignore_case);
void str_upcase(char *s);
void str_downcase(char *s);
extern LogoVal *LOGO_TRUE;
extern LogoVal *LOGO_FALSE;
extern LogoVal *LOGO_EMPTY_WORD;
#endif
''')

write('src/gc.h', r'''
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
''')

write('src/tokenizer.h', r'''
#ifndef LOCO_TOKENIZER_H
#define LOCO_TOKENIZER_H
typedef enum {
    TK_EOF, TK_NEWLINE, TK_NUMBER, TK_WORD, TK_NAME,
    TK_VAR, TK_LBRACKET, TK_RBRACKET, TK_LPAREN, TK_RPAREN,
    TK_LBRACE, TK_RBRACE, TK_INFIX, TK_TILDE,
} TokenType;
typedef struct { TokenType type; char value[512]; } Token;
typedef struct { const char *src; int pos, len, inside_brackets; } Tokenizer;
void tokenizer_init(Tokenizer *t, const char *src);
Token tokenizer_next(Tokenizer *t);
Token tokenizer_peek(Tokenizer *t);
int tokenizer_done(Tokenizer *t);
typedef struct { Token *tokens; int pos, count, capacity; } TokenStream;
void ts_init(TokenStream *ts);
void ts_free(TokenStream *ts);
void ts_append(TokenStream *ts, Token tok);
void tokenize(const char *src, TokenStream *ts);
Token ts_peek(TokenStream *ts);
Token ts_consume(TokenStream *ts);
int ts_done(TokenStream *ts);
int ts_at_end_of_instruction(TokenStream *ts);
void ts_skip_newlines(TokenStream *ts);
Token ts_peek_skip_newlines(TokenStream *ts);
#endif
''')

write('src/env.h', r'''
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
''')

write('src/workspace.h', r'''
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
''')

write('src/interp.h', r'''
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
''')

write('src/primitives.h', r'''
#ifndef LOCO_PRIMITIVES_H
#define LOCO_PRIMITIVES_H
#include "interp.h"
void register_data_primitives(Interp *interp);
void register_arith_primitives(Interp *interp);
void register_logic_primitives(Interp *interp);
void register_comm_primitives(Interp *interp);
void register_file_primitives(Interp *interp);
void register_ctrl_primitives(Interp *interp);
void register_ws_primitives(Interp *interp);
void register_tmpl_primitives(Interp *interp);
#define REG(name, min, def, max, fn) \
    ws_define(&interp->ws, make_primitive(name, min, def, max, fn))
#define CHECK_WORD(v, name) \
    if (!(v) || (v)->type != LV_WORD) interp_error(interp, "%s requires a word", name)
#define CHECK_NUM(v, name) \
    if (!logo_is_number(v)) interp_error(interp, "%s requires a number", name)
#define CHECK_LIST(v, name) \
    if ((v) && (v)->type == LV_ARRAY) interp_error(interp, "%s requires a list (not array)", name)
#endif
''')

print("Header files written")

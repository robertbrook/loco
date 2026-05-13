#include <ctype.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MAX_LINE_LENGTH 8192

typedef enum {
    VAL_NONE,
    VAL_NUM,
    VAL_WORD,
    VAL_LIST
} ValueType;

typedef struct {
    ValueType type;
    double num;
    char *word;
} Value;

typedef struct Var {
    char *name;
    Value value;
    struct Var *next;
} Var;

typedef struct Scope {
    Var *vars;
    struct Scope *parent;
} Scope;

typedef struct Proc {
    char *name;
    char **params;
    int param_count;
    char *body;
    bool is_macro;
    struct Proc *next;
} Proc;

typedef struct {
    bool active;
    bool is_macro;
    char *name;
    char **params;
    int param_count;
    char *body;
    size_t body_len;
    size_t body_cap;
} ProcBuilder;

typedef struct {
    Scope *global_scope;
    Scope *current_scope;
    Proc *procs;
    ProcBuilder builder;
    bool had_error;
    bool stop;
    bool has_output;
    Value output;
} Interp;

static char *dupstr(const char *s) {
    size_t n = strlen(s);
    char *out = (char *)malloc(n + 1);
    if (!out) {
        fprintf(stderr, "out of memory\n");
        exit(1);
    }
    memcpy(out, s, n + 1);
    return out;
}

static Value v_none(void) { return (Value){.type = VAL_NONE, .num = 0, .word = NULL}; }
static Value v_num(double n) { return (Value){.type = VAL_NUM, .num = n, .word = NULL}; }
static Value v_word(const char *s) { return (Value){.type = VAL_WORD, .num = 0, .word = dupstr(s)}; }
static Value v_list(const char *s) { return (Value){.type = VAL_LIST, .num = 0, .word = dupstr(s ? s : "")}; }

static void v_free(Value *v) {
    if ((v->type == VAL_WORD || v->type == VAL_LIST) && v->word) free(v->word);
    *v = v_none();
}

static Value v_copy(Value v) {
    if (v.type == VAL_WORD && v.word) return v_word(v.word);
    if (v.type == VAL_LIST) return v_list(v.word);
    return v;
}

static bool parse_num(const char *s, double *out) {
    char *end = NULL;
    double n = strtod(s, &end);
    if (end == s || *end != '\0') return false;
    *out = n;
    return true;
}

static double to_num(Value v) {
    if (v.type == VAL_NUM) return v.num;
    if (v.type == VAL_WORD && v.word) {
        double n = 0;
        if (parse_num(v.word, &n)) return n;
    }
    return 0;
}

static void print_value(Value v) {
    if (v.type == VAL_NUM) {
        long long integer_part = (long long)v.num;
        if ((double)integer_part == v.num) printf("%lld\n", integer_part);
        else printf("%g\n", v.num);
    } else if (v.type == VAL_WORD && v.word) {
        printf("%s\n", v.word);
    } else if (v.type == VAL_LIST) {
        printf("[%s]\n", v.word ? v.word : "");
    } else {
        printf("\n");
    }
}

static Scope *scope_new(Scope *parent) {
    Scope *s = (Scope *)calloc(1, sizeof(*s));
    if (!s) { fprintf(stderr, "out of memory\n"); exit(1); }
    s->parent = parent;
    return s;
}

static void scope_free(Scope *s) {
    Var *v = s->vars;
    while (v) {
        Var *next_var = v->next;
        free(v->name);
        v_free(&v->value);
        free(v);
        v = next_var;
    }
    free(s);
}

static Var *find_local(Scope *s, const char *name) {
    for (Var *v = s->vars; v; v = v->next) if (!strcmp(v->name, name)) return v;
    return NULL;
}

static Var *find_var(Scope *s, const char *name) {
    for (Scope *cur = s; cur; cur = cur->parent) {
        Var *v = find_local(cur, name);
        if (v) return v;
    }
    return NULL;
}

static void set_var(Scope *s, const char *name, Value val) {
    Var *existing = find_var(s, name);
    if (existing) {
        v_free(&existing->value);
        existing->value = v_copy(val);
        return;
    }
    Var *v = (Var *)calloc(1, sizeof(*v));
    if (!v) { fprintf(stderr, "out of memory\n"); exit(1); }
    v->name = dupstr(name);
    v->value = v_copy(val);
    v->next = s->vars;
    s->vars = v;
}

static Proc *find_proc(Interp *it, const char *name) {
    for (Proc *p = it->procs; p; p = p->next) if (!strcmp(p->name, name)) return p;
    return NULL;
}

static void free_proc(Proc *p) {
    free(p->name);
    for (int i = 0; i < p->param_count; i++) free(p->params[i]);
    free(p->params);
    free(p->body);
    free(p);
}

static void set_proc(Interp *it, Proc *np) {
    Proc *prev = NULL;
    for (Proc *p = it->procs; p; p = p->next) {
        if (!strcmp(p->name, np->name)) {
            if (prev) prev->next = np;
            else it->procs = np;
            np->next = p->next;
            free_proc(p);
            return;
        }
        prev = p;
    }
    np->next = it->procs;
    it->procs = np;
}

static int find_close_bracket(char **toks, int n, int open_idx) {
    int depth = 0;
    for (int i = open_idx; i < n; i++) {
        if (!strcmp(toks[i], "[")) depth++;
        else if (!strcmp(toks[i], "]")) {
            depth--;
            if (depth == 0) return i;
        }
    }
    return -1;
}

static void tokenize(const char *line, char ***out_toks, int *out_n) {
    int cap = 16, token_count = 0;
    char **toks = (char **)malloc((size_t)cap * sizeof(*toks));
    if (!toks) { fprintf(stderr, "out of memory\n"); exit(1); }
    for (const char *p = line; *p;) {
        while (*p && isspace((unsigned char)*p)) p++;
        if (!*p || *p == ';') break;
        const char *start = p;
        size_t len = 0;
        if (*p == '[' || *p == ']') {
            p++;
            len = 1;
        } else {
            while (*p && !isspace((unsigned char)*p) && *p != '[' && *p != ']' && *p != ';') p++;
            len = (size_t)(p - start);
        }
        char *tok = (char *)malloc(len + 1);
        if (!tok) { fprintf(stderr, "out of memory\n"); exit(1); }
        memcpy(tok, start, len);
        tok[len] = '\0';
        if (token_count == cap) {
            cap *= 2;
            toks = (char **)realloc(toks, (size_t)cap * sizeof(*toks));
            if (!toks) { fprintf(stderr, "out of memory\n"); exit(1); }
        }
        toks[token_count++] = tok;
    }
    *out_toks = toks;
    *out_n = token_count;
}

static void free_tokens(char **toks, int n) {
    for (int i = 0; i < n; i++) free(toks[i]);
    free(toks);
}

static Value eval_expr(Interp *it, char **toks, int n, int *idx);
static bool exec_tokens(Interp *it, char **toks, int n, int *idx);
static Value run_list_capture(Interp *it, Value body);

static Value invoke_proc(Interp *it, Proc *p, Value *args) {
    Scope *local = scope_new(it->current_scope);
    it->current_scope = local;
    for (int i = 0; i < p->param_count; i++) set_var(local, p->params[i], args[i]);

    bool saved_stop = it->stop;
    bool saved_out = it->has_output;
    Value saved_output = v_copy(it->output);
    it->stop = false;
    it->has_output = false;
    v_free(&it->output);

    char *body = dupstr(p->body);
    char *cursor = body;
    while (*cursor) {
        char *line = cursor;
        while (*cursor && *cursor != '\n') cursor++;
        if (*cursor == '\n') *cursor++ = '\0';
        char **toks = NULL;
        int tn = 0;
        tokenize(line, &toks, &tn);
        int i = 0;
        if (tn > 0) exec_tokens(it, toks, tn, &i);
        free_tokens(toks, tn);
        if (it->stop || it->has_output) break;
    }
    free(body);

    Value out = it->has_output ? v_copy(it->output) : v_none();
    it->stop = saved_stop;
    it->has_output = saved_out;
    v_free(&it->output);
    it->output = saved_output;
    it->current_scope = local->parent;
    scope_free(local);
    return out;
}

static Value run_list_capture(Interp *it, Value body) {
    if (body.type != VAL_LIST) {
        fprintf(stderr, "error: run requires a list\n");
        it->had_error = true;
        return v_none();
    }
    char **ltoks = NULL; int ln = 0;
    tokenize(body.word ? body.word : "", &ltoks, &ln);
    bool saved_stop = it->stop;
    bool saved_out = it->has_output;
    Value saved_output = v_copy(it->output);
    it->stop = false;
    it->has_output = false;
    v_free(&it->output);
    it->output = v_none();
    int li = 0;
    exec_tokens(it, ltoks, ln, &li);
    free_tokens(ltoks, ln);
    Value out = it->has_output ? v_copy(it->output) : v_none();
    it->stop = saved_stop;
    it->has_output = saved_out;
    v_free(&it->output);
    it->output = saved_output;
    return out;
}

static Value eval_expr(Interp *it, char **toks, int n, int *idx) {
    if (*idx >= n) return v_none();
    char *t = toks[(*idx)++];

    if (t[0] == '"') return v_word(t + 1);
    if (t[0] == ':') {
        Var *v = find_var(it->current_scope, t + 1);
        if (!v) { fprintf(stderr, "error: unknown variable '%s'\n", t + 1); it->had_error = true; return v_none(); }
        return v_copy(v->value);
    }
    double num = 0;
    if (parse_num(t, &num)) return v_num(num);

    if (!strcmp(t, "sum") || !strcmp(t, "difference") || !strcmp(t, "product") || !strcmp(t, "quotient")) {
        Value a = eval_expr(it, toks, n, idx), b = eval_expr(it, toks, n, idx);
        double av = to_num(a), bv = to_num(b), out = 0;
        if (!strcmp(t, "sum")) out = av + bv;
        if (!strcmp(t, "difference")) out = av - bv;
        if (!strcmp(t, "product")) out = av * bv;
        if (!strcmp(t, "quotient")) {
            if (bv == 0) {
                fprintf(stderr, "error: division by zero\n");
                it->had_error = true;
                out = 0;
            } else {
                out = av / bv;
            }
        }
        v_free(&a); v_free(&b);
        return v_num(out);
    }
    if (!strcmp(t, "lessp") || !strcmp(t, "greaterp") || !strcmp(t, "equalp")) {
        Value a = eval_expr(it, toks, n, idx), b = eval_expr(it, toks, n, idx);
        double out = 0;
        if (!strcmp(t, "lessp")) out = to_num(a) < to_num(b);
        if (!strcmp(t, "greaterp")) out = to_num(a) > to_num(b);
        if (!strcmp(t, "equalp")) {
            if (a.type == VAL_WORD || b.type == VAL_WORD) {
                const char *aw = (a.type == VAL_WORD && a.word) ? a.word : "";
                const char *bw = (b.type == VAL_WORD && b.word) ? b.word : "";
                out = !strcmp(aw, bw);
            } else out = to_num(a) == to_num(b);
        }
        v_free(&a); v_free(&b);
        return v_num(out);
    }
    if (!strcmp(t, "thing")) {
        Value name = eval_expr(it, toks, n, idx);
        const char *var = (name.type == VAL_WORD && name.word) ? name.word : "";
        Var *v = find_var(it->current_scope, var);
        Value out = v ? v_copy(v->value) : v_none();
        if (!v) { fprintf(stderr, "error: unknown variable '%s'\n", var); it->had_error = true; }
        v_free(&name);
        return out;
    }

    if (!strcmp(t, "[")) {
        int open = *idx - 1;
        int close = find_close_bracket(toks, n, open);
        if (close < 0) { fprintf(stderr, "error: unmatched '['\n"); it->had_error = true; return v_none(); }
        size_t total = 0;
        for (int i = open + 1; i < close; i++) total += strlen(toks[i]) + 1;
        char *buf = (char *)malloc(total + 1);
        if (!buf) { fprintf(stderr, "out of memory\n"); exit(1); }
        size_t pos = 0;
        for (int i = open + 1; i < close; i++) {
            if (i > open + 1) buf[pos++] = ' ';
            size_t slen = strlen(toks[i]);
            memcpy(buf + pos, toks[i], slen);
            pos += slen;
        }
        buf[pos] = '\0';
        *idx = close + 1;
        return (Value){.type = VAL_LIST, .num = 0, .word = buf};
    }
    if (!strcmp(t, "run")) {
        Value body = eval_expr(it, toks, n, idx);
        Value out = run_list_capture(it, body);
        v_free(&body);
        return out;
    }

    Proc *p = find_proc(it, t);
    if (p) {
        Value *args = (Value *)calloc((size_t)p->param_count, sizeof(*args));
        if (!args) { fprintf(stderr, "out of memory\n"); exit(1); }
        for (int i = 0; i < p->param_count; i++) args[i] = eval_expr(it, toks, n, idx);
        Value r = invoke_proc(it, p, args);
        for (int i = 0; i < p->param_count; i++) v_free(&args[i]);
        free(args);
        if (p->is_macro) {
            Value out = run_list_capture(it, r);
            v_free(&r);
            return out;
        }
        return r;
    }

    return v_word(t);
}

static bool exec_tokens(Interp *it, char **toks, int n, int *idx) {
    while (*idx < n) {
        char *cmd = toks[*idx];
        if (!strcmp(cmd, "]")) { fprintf(stderr, "error: unexpected ']'\n"); it->had_error = true; return false; }
        (*idx)++;

        if (!strcmp(cmd, "print")) {
            Value v = eval_expr(it, toks, n, idx);
            print_value(v);
            v_free(&v);
            continue;
        }
        if (!strcmp(cmd, "make")) {
            if (*idx >= n) { fprintf(stderr, "error: make requires name\n"); it->had_error = true; return false; }
            char *name_tok = toks[(*idx)++];
            const char *name = name_tok[0] == '"' ? name_tok + 1 : name_tok;
            Value v = eval_expr(it, toks, n, idx);
            set_var(it->current_scope, name, v);
            v_free(&v);
            continue;
        }
        if (!strcmp(cmd, "repeat")) {
            Value c = eval_expr(it, toks, n, idx);
            int times = (int)to_num(c);
            v_free(&c);
            Value body = eval_expr(it, toks, n, idx);
            if (body.type != VAL_LIST) { fprintf(stderr, "error: repeat requires a list\n"); it->had_error = true; v_free(&body); return false; }
            char **ltoks = NULL; int ln = 0;
            tokenize(body.word ? body.word : "", &ltoks, &ln);
            v_free(&body);
            for (int r = 0; r < times && !it->stop && !it->has_output; r++) {
                int li = 0;
                if (!exec_tokens(it, ltoks, ln, &li)) { free_tokens(ltoks, ln); return false; }
            }
            free_tokens(ltoks, ln);
            if (it->stop || it->has_output) return true;
            continue;
        }
        if (!strcmp(cmd, "if") || !strcmp(cmd, "ifelse")) {
            Value c = eval_expr(it, toks, n, idx);
            bool cond = to_num(c) != 0;
            v_free(&c);
            Value tbody = eval_expr(it, toks, n, idx);
            Value fbody = v_none();
            if (!strcmp(cmd, "ifelse")) fbody = eval_expr(it, toks, n, idx);
            if (tbody.type != VAL_LIST) { fprintf(stderr, "error: if requires a list\n"); it->had_error = true; v_free(&tbody); v_free(&fbody); return false; }
            if (!strcmp(cmd, "ifelse") && fbody.type != VAL_LIST) { fprintf(stderr, "error: ifelse requires two lists\n"); it->had_error = true; v_free(&tbody); v_free(&fbody); return false; }
            Value branch = cond ? v_copy(tbody) : v_copy(fbody);
            v_free(&tbody); v_free(&fbody);
            if (branch.type == VAL_LIST) {
                char **ltoks = NULL; int ln = 0;
                tokenize(branch.word ? branch.word : "", &ltoks, &ln);
                int li = 0;
                exec_tokens(it, ltoks, ln, &li);
                free_tokens(ltoks, ln);
            }
            v_free(&branch);
            if (it->stop || it->has_output) return true;
            continue;
        }
        if (!strcmp(cmd, "output")) {
            v_free(&it->output);
            it->output = eval_expr(it, toks, n, idx);
            it->has_output = true;
            return true;
        }
        if (!strcmp(cmd, "stop")) {
            it->stop = true;
            return true;
        }
        if (!strcmp(cmd, "run")) {
            Value body = eval_expr(it, toks, n, idx);
            if (body.type != VAL_LIST) {
                fprintf(stderr, "error: run requires a list\n");
                it->had_error = true;
                v_free(&body);
                return false;
            }
            char **ltoks = NULL; int ln = 0;
            tokenize(body.word ? body.word : "", &ltoks, &ln);
            v_free(&body);
            int li = 0;
            exec_tokens(it, ltoks, ln, &li);
            free_tokens(ltoks, ln);
            if (it->stop || it->has_output) return true;
            continue;
        }

        Proc *p = find_proc(it, cmd);
        if (!p) { fprintf(stderr, "error: unknown command '%s'\n", cmd); it->had_error = true; return false; }
        Value *args = (Value *)calloc((size_t)p->param_count, sizeof(*args));
        if (!args) { fprintf(stderr, "out of memory\n"); exit(1); }
        for (int i = 0; i < p->param_count; i++) args[i] = eval_expr(it, toks, n, idx);
        Value r = invoke_proc(it, p, args);
        for (int i = 0; i < p->param_count; i++) v_free(&args[i]);
        free(args);
        if (p->is_macro) {
            if (r.type == VAL_LIST) {
                char **ltoks = NULL; int ln = 0;
                tokenize(r.word ? r.word : "", &ltoks, &ln);
                v_free(&r);
                int li = 0;
                exec_tokens(it, ltoks, ln, &li);
                free_tokens(ltoks, ln);
            } else if (r.type != VAL_NONE) {
                fprintf(stderr, "error: macro must output a list\n");
                it->had_error = true;
                v_free(&r);
            } else {
                v_free(&r);
            }
        } else {
            v_free(&r);
        }
        if (it->stop || it->has_output) return true;
    }
    return true;
}

static void builder_reset(ProcBuilder *b) {
    b->active = false;
    b->is_macro = false;
    free(b->name); b->name = NULL;
    for (int i = 0; i < b->param_count; i++) free(b->params[i]);
    free(b->params); b->params = NULL;
    b->param_count = 0;
    free(b->body); b->body = NULL; b->body_len = 0; b->body_cap = 0;
}

static void builder_append(ProcBuilder *b, const char *line) {
    size_t n = strlen(line);
    size_t need = b->body_len + n + 2;
    if (need > b->body_cap) {
        size_t cap = b->body_cap ? b->body_cap : 128;
        while (cap < need) cap *= 2;
        b->body = (char *)realloc(b->body, cap);
        if (!b->body) { fprintf(stderr, "out of memory\n"); exit(1); }
        b->body_cap = cap;
    }
    memcpy(b->body + b->body_len, line, n);
    b->body_len += n;
    b->body[b->body_len++] = '\n';
    b->body[b->body_len] = '\0';
}

static void start_proc(Interp *it, char **toks, int n, bool is_macro) {
    if (n < 2) { fprintf(stderr, "error: %s requires a name\n", is_macro ? "macro" : "to"); it->had_error = true; return; }
    builder_reset(&it->builder);
    it->builder.active = true;
    it->builder.is_macro = is_macro;
    it->builder.name = dupstr(toks[1]);
    for (int i = 2; i < n; i++) {
        if (toks[i][0] != ':') { fprintf(stderr, "error: parameter must start with ':'\n"); it->had_error = true; continue; }
        char **p = (char **)realloc(it->builder.params, (size_t)(it->builder.param_count + 1) * sizeof(char *));
        if (!p) { fprintf(stderr, "out of memory\n"); exit(1); }
        it->builder.params = p;
        it->builder.params[it->builder.param_count++] = dupstr(toks[i] + 1);
    }
}

static void finish_proc(Interp *it) {
    Proc *p = (Proc *)calloc(1, sizeof(*p));
    if (!p) { fprintf(stderr, "out of memory\n"); exit(1); }
    p->name = it->builder.name;
    p->params = it->builder.params;
    p->param_count = it->builder.param_count;
    p->body = it->builder.body ? it->builder.body : dupstr("");
    p->is_macro = it->builder.is_macro;
    it->builder.name = NULL;
    it->builder.params = NULL;
    it->builder.param_count = 0;
    it->builder.body = NULL;
    it->builder.body_len = it->builder.body_cap = 0;
    it->builder.active = false;
    set_proc(it, p);
}

static void execute_line(Interp *it, const char *line) {
    char **toks = NULL;
    int n = 0;
    tokenize(line, &toks, &n);
    if (n == 0) { free_tokens(toks, n); return; }
    if (it->builder.active) {
        if (!strcmp(toks[0], "end")) finish_proc(it);
        else builder_append(&it->builder, line);
        free_tokens(toks, n);
        return;
    }
    if (!strcmp(toks[0], "to")) { start_proc(it, toks, n, false); free_tokens(toks, n); return; }
    if (!strcmp(toks[0], "macro")) { start_proc(it, toks, n, true); free_tokens(toks, n); return; }
    int i = 0;
    exec_tokens(it, toks, n, &i);
    free_tokens(toks, n);
}

static void interp_init(Interp *it) {
    memset(it, 0, sizeof(*it));
    it->global_scope = scope_new(NULL);
    it->current_scope = it->global_scope;
    it->output = v_none();
}

static void interp_free(Interp *it) {
    builder_reset(&it->builder);
    while (it->procs) {
        Proc *next_proc = it->procs->next;
        free_proc(it->procs);
        it->procs = next_proc;
    }
    while (it->current_scope != it->global_scope) {
        Scope *parent_scope = it->current_scope->parent;
        scope_free(it->current_scope);
        it->current_scope = parent_scope;
    }
    if (it->global_scope) scope_free(it->global_scope);
    v_free(&it->output);
}

static void run_stream(Interp *it, FILE *f) {
    char line[MAX_LINE_LENGTH];
    bool interactive = (f == stdin) && isatty(STDIN_FILENO);
    while (1) {
        if (interactive) { fputs("> ", stdout); fflush(stdout); }
        if (!fgets(line, sizeof(line), f)) break;
        size_t len = strlen(line);
        if (len > 0 && line[len - 1] != '\n' && !feof(f)) {
            int c;
            while ((c = fgetc(f)) != '\n' && c != EOF) {}
            fprintf(stderr, "error: input line too long (max %d bytes)\n", MAX_LINE_LENGTH - 1);
            it->had_error = true;
            continue;
        }
        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r')) line[--len] = '\0';
        execute_line(it, line);
    }
    if (it->builder.active) { fprintf(stderr, "error: missing 'end' for procedure\n"); it->had_error = true; }
}

int main(int argc, char **argv) {
    if (argc > 2) {
        fprintf(stderr, "usage: %s [script.logo]\n", argv[0]);
        return 1;
    }
    Interp it;
    interp_init(&it);
    if (argc == 2) {
        FILE *f = fopen(argv[1], "r");
        if (!f) { perror("fopen"); interp_free(&it); return 1; }
        run_stream(&it, f);
        fclose(f);
    } else {
        run_stream(&it, stdin);
    }
    int code = it.had_error ? 1 : 0;
    interp_free(&it);
    return code;
}

#include <ctype.h>
#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#ifdef HAVE_READLINE
#include <readline/readline.h>
#include <readline/history.h>
#endif

#define MAX_LINE_LENGTH 8192

typedef enum {
    VAL_NONE,
    VAL_NUM,
    VAL_WORD
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
    struct Proc *next;
} Proc;

typedef struct Prop {
    char *name;
    char *prop;
    Value value;
    struct Prop *next;
} Prop;

typedef struct {
    bool active;
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
    Prop *props;
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

static void tokenize(const char *line, char ***out_toks, int *out_n);

static Value v_none(void) { return (Value){.type = VAL_NONE, .num = 0, .word = NULL}; }
static Value v_num(double n) { return (Value){.type = VAL_NUM, .num = n, .word = NULL}; }
static Value v_word(const char *s) { return (Value){.type = VAL_WORD, .num = 0, .word = dupstr(s)}; }

static void v_free(Value *v) {
    if (v->type == VAL_WORD && v->word) free(v->word);
    *v = v_none();
}

static Value v_copy(Value v) {
    if (v.type == VAL_WORD && v.word) return v_word(v.word);
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
    } else {
        printf("\n");
    }
}

static bool is_truthy(Value v) {
    if (v.type == VAL_NUM) return v.num != 0;
    if (v.type == VAL_WORD && v.word) {
        if (!strcmp(v.word, "true")) return true;
        if (!strcmp(v.word, "false")) return false;
        double n = 0;
        if (parse_num(v.word, &n)) return n != 0;
        return v.word[0] != '\0';
    }
    return false;
}

static char *value_to_text(Value v) {
    if (v.type == VAL_WORD && v.word) return dupstr(v.word);
    if (v.type == VAL_NUM) {
        char buf[64];
        long long integer_part = (long long)v.num;
        if ((double)integer_part == v.num) snprintf(buf, sizeof(buf), "%lld", integer_part);
        else snprintf(buf, sizeof(buf), "%g", v.num);
        return dupstr(buf);
    }
    return dupstr("");
}

static bool is_list_word(Value v) {
    if (v.type != VAL_WORD || !v.word) return false;
    size_t n = strlen(v.word);
    return n >= 2 && v.word[0] == '[' && v.word[n - 1] == ']';
}

static char *list_inner_text(const char *list_word) {
    size_t n = strlen(list_word);
    if (n < 2) return dupstr("");
    char *out = (char *)malloc(n - 1);
    if (!out) { fprintf(stderr, "out of memory\n"); exit(1); }
    memcpy(out, list_word + 1, n - 2);
    out[n - 2] = '\0';
    return out;
}

static char *join_tokens_as_list(char **toks, int n) {
    size_t total = 2;
    for (int i = 0; i < n; i++) total += strlen(toks[i]) + 1;
    char *out = (char *)malloc(total + 1);
    if (!out) { fprintf(stderr, "out of memory\n"); exit(1); }
    size_t pos = 0;
    out[pos++] = '[';
    for (int i = 0; i < n; i++) {
        size_t len = strlen(toks[i]);
        memcpy(out + pos, toks[i], len);
        pos += len;
        if (i + 1 < n) out[pos++] = ' ';
    }
    out[pos++] = ']';
    out[pos] = '\0';
    return out;
}

static bool list_to_items(Value list, char ***out_toks, int *out_n) {
    if (!is_list_word(list)) return false;
    char *inner = list_inner_text(list.word);
    tokenize(inner, out_toks, out_n);
    free(inner);
    return true;
}

static char *tokens_to_text(char **toks, int from, int to) {
    size_t total = 0;
    for (int i = from; i < to; i++) total += strlen(toks[i]) + 1;
    char *out = (char *)malloc(total + 1);
    if (!out) { fprintf(stderr, "out of memory\n"); exit(1); }
    size_t pos = 0;
    for (int i = from; i < to; i++) {
        size_t len = strlen(toks[i]);
        memcpy(out + pos, toks[i], len);
        pos += len;
        if (i + 1 < to) out[pos++] = ' ';
    }
    out[pos] = '\0';
    return out;
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

static Prop *find_prop(Interp *it, const char *name, const char *prop) {
    for (Prop *p = it->props; p; p = p->next) {
        if (!strcmp(p->name, name) && !strcmp(p->prop, prop)) return p;
    }
    return NULL;
}

static void put_prop(Interp *it, const char *name, const char *prop, Value v) {
    Prop *existing = find_prop(it, name, prop);
    if (existing) {
        v_free(&existing->value);
        existing->value = v_copy(v);
        return;
    }
    Prop *p = (Prop *)calloc(1, sizeof(*p));
    if (!p) { fprintf(stderr, "out of memory\n"); exit(1); }
    p->name = dupstr(name);
    p->prop = dupstr(prop);
    p->value = v_copy(v);
    p->next = it->props;
    it->props = p;
}

static bool remove_prop(Interp *it, const char *name, const char *prop) {
    Prop *prev = NULL;
    for (Prop *p = it->props; p; p = p->next) {
        if (!strcmp(p->name, name) && !strcmp(p->prop, prop)) {
            if (prev) prev->next = p->next;
            else it->props = p->next;
            free(p->name);
            free(p->prop);
            v_free(&p->value);
            free(p);
            return true;
        }
        prev = p;
    }
    return false;
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

static void set_local_var(Scope *s, const char *name, Value val) {
    Var *existing = find_local(s, name);
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
    if (!strcmp(t, "[")) {
        int open = *idx - 1;
        int close = find_close_bracket(toks, n, open);
        if (close < 0) { fprintf(stderr, "error: unmatched '['\n"); it->had_error = true; return v_none(); }
        char *list_text = tokens_to_text(toks, open, close + 1);
        *idx = close + 1;
        Value out = v_word(list_text);
        free(list_text);
        return out;
    }

    if (!strcmp(t, "pi")) return v_num(3.14159265358979323846);

    if (!strcmp(t, "sum") || !strcmp(t, "difference") || !strcmp(t, "product") || !strcmp(t, "quotient") ||
        !strcmp(t, "power") || !strcmp(t, "remainder") || !strcmp(t, "atan2") || !strcmp(t, "aTan2")) {
        Value a = eval_expr(it, toks, n, idx), b = eval_expr(it, toks, n, idx);
        double av = to_num(a), bv = to_num(b), out = 0;
        if (!strcmp(t, "sum")) out = av + bv;
        if (!strcmp(t, "difference")) out = av - bv;
        if (!strcmp(t, "product")) out = av * bv;
        if (!strcmp(t, "power")) out = pow(av, bv);
        if (!strcmp(t, "atan2") || !strcmp(t, "aTan2")) out = atan2(bv, av) * (180.0 / 3.14159265358979323846);
        if (!strcmp(t, "remainder")) {
            if (bv == 0) {
                fprintf(stderr, "error: division by zero\n");
                it->had_error = true;
            } else out = fmod(av, bv);
        }
        if (!strcmp(t, "quotient")) {
            if (bv == 0) {
                fprintf(stderr, "error: division by zero\n");
                it->had_error = true;
            } else out = av / bv;
        }
        v_free(&a); v_free(&b);
        return v_num(out);
    }

    if (!strcmp(t, "date")) {
        time_t now = time(NULL);
        struct tm tmv;
        localtime_r(&now, &tmv);
        char out[32];
        strftime(out, sizeof(out), "%Y-%m-%d", &tmv);
        return v_word(out);
    }
    if (!strcmp(t, "time")) {
        time_t now = time(NULL);
        struct tm tmv;
        localtime_r(&now, &tmv);
        char out[32];
        strftime(out, sizeof(out), "%H:%M:%S", &tmv);
        return v_word(out);
    }

    if (!strcmp(t, "abs") || !strcmp(t, "sqrt") || !strcmp(t, "exp") || !strcmp(t, "log") || !strcmp(t, "log10") ||
        !strcmp(t, "sin") || !strcmp(t, "cos") || !strcmp(t, "tan") ||
        !strcmp(t, "arcsin") || !strcmp(t, "arccos") || !strcmp(t, "arctan") ||
        !strcmp(t, "arcSin") || !strcmp(t, "arcCos") || !strcmp(t, "arcTan") ||
        !strcmp(t, "sinh") || !strcmp(t, "cosh") || !strcmp(t, "tanh") ||
        !strcmp(t, "integer") || !strcmp(t, "round") || !strcmp(t, "random")) {
        Value a = eval_expr(it, toks, n, idx);
        double av = to_num(a), out = 0;
        if (!strcmp(t, "abs")) out = fabs(av);
        else if (!strcmp(t, "sqrt")) out = sqrt(av);
        else if (!strcmp(t, "exp")) out = exp(av);
        else if (!strcmp(t, "log")) out = log(av);
        else if (!strcmp(t, "log10")) out = log10(av);
        else if (!strcmp(t, "sin")) out = sin(av * (3.14159265358979323846 / 180.0));
        else if (!strcmp(t, "cos")) out = cos(av * (3.14159265358979323846 / 180.0));
        else if (!strcmp(t, "tan")) out = tan(av * (3.14159265358979323846 / 180.0));
        else if (!strcmp(t, "arcsin") || !strcmp(t, "arcSin")) out = asin(av) * (180.0 / 3.14159265358979323846);
        else if (!strcmp(t, "arccos") || !strcmp(t, "arcCos")) out = acos(av) * (180.0 / 3.14159265358979323846);
        else if (!strcmp(t, "arctan") || !strcmp(t, "arcTan")) out = atan(av) * (180.0 / 3.14159265358979323846);
        else if (!strcmp(t, "sinh")) out = sinh(av);
        else if (!strcmp(t, "cosh")) out = cosh(av);
        else if (!strcmp(t, "tanh")) out = tanh(av);
        else if (!strcmp(t, "integer")) out = (double)((long long)av);
        else if (!strcmp(t, "round")) out = round(av);
        else if (!strcmp(t, "random")) {
            long long limit = (long long)av;
            if (limit <= 0) out = 0;
            else out = (double)(rand() % limit);
        }
        v_free(&a);
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

    if (!strcmp(t, "and") || !strcmp(t, "or")) {
        Value a = eval_expr(it, toks, n, idx), b = eval_expr(it, toks, n, idx);
        bool out = !strcmp(t, "and") ? (is_truthy(a) && is_truthy(b)) : (is_truthy(a) || is_truthy(b));
        v_free(&a); v_free(&b);
        return v_num(out ? 1 : 0);
    }
    if (!strcmp(t, "not")) {
        Value a = eval_expr(it, toks, n, idx);
        bool out = !is_truthy(a);
        v_free(&a);
        return v_num(out ? 1 : 0);
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
    if (!strcmp(t, "namep")) {
        Value name = eval_expr(it, toks, n, idx);
        const char *var = (name.type == VAL_WORD && name.word) ? name.word : "";
        Var *v = find_var(it->current_scope, var);
        v_free(&name);
        return v_num(v != NULL);
    }
    if (!strcmp(t, "definep")) {
        Value name = eval_expr(it, toks, n, idx);
        const char *proc = (name.type == VAL_WORD && name.word) ? name.word : "";
        Proc *p = find_proc(it, proc);
        v_free(&name);
        return v_num(p != NULL);
    }
    if (!strcmp(t, "numberp")) {
        Value a = eval_expr(it, toks, n, idx);
        bool ok = (a.type == VAL_NUM);
        if (!ok && a.type == VAL_WORD && a.word) {
            double ncheck = 0;
            ok = parse_num(a.word, &ncheck);
        }
        v_free(&a);
        return v_num(ok ? 1 : 0);
    }
    if (!strcmp(t, "listp")) {
        Value a = eval_expr(it, toks, n, idx);
        bool ok = is_list_word(a);
        v_free(&a);
        return v_num(ok ? 1 : 0);
    }
    if (!strcmp(t, "wordp")) {
        Value a = eval_expr(it, toks, n, idx);
        bool ok = !is_list_word(a);
        v_free(&a);
        return v_num(ok ? 1 : 0);
    }
    if (!strcmp(t, "emptyp")) {
        Value a = eval_expr(it, toks, n, idx);
        bool empty = false;
        if (is_list_word(a)) {
            char **lt = NULL;
            int ln = 0;
            list_to_items(a, &lt, &ln);
            empty = ln == 0;
            free_tokens(lt, ln);
        } else {
            char *txt = value_to_text(a);
            empty = txt[0] == '\0';
            free(txt);
        }
        v_free(&a);
        return v_num(empty ? 1 : 0);
    }

    if (!strcmp(t, "ascii")) {
        Value a = eval_expr(it, toks, n, idx);
        char *txt = value_to_text(a);
        int out = (txt[0] != '\0') ? (unsigned char)txt[0] : 0;
        free(txt);
        v_free(&a);
        return v_num(out);
    }
    if (!strcmp(t, "char")) {
        Value a = eval_expr(it, toks, n, idx);
        int c = (int)to_num(a);
        v_free(&a);
        char out[2] = {(char)c, '\0'};
        return v_word(out);
    }
    if (!strcmp(t, "uppercase") || !strcmp(t, "lowercase")) {
        Value a = eval_expr(it, toks, n, idx);
        char *txt = value_to_text(a);
        for (char *p = txt; *p; p++) *p = !strcmp(t, "uppercase") ? (char)toupper((unsigned char)*p) : (char)tolower((unsigned char)*p);
        Value out = v_word(txt);
        free(txt);
        v_free(&a);
        return out;
    }
    if (!strcmp(t, "count")) {
        Value a = eval_expr(it, toks, n, idx);
        int out = 0;
        if (is_list_word(a)) {
            char **lt = NULL;
            int ln = 0;
            list_to_items(a, &lt, &ln);
            out = ln;
            free_tokens(lt, ln);
        } else {
            char *txt = value_to_text(a);
            out = (int)strlen(txt);
            free(txt);
        }
        v_free(&a);
        return v_num(out);
    }
    if (!strcmp(t, "first") || !strcmp(t, "last")) {
        Value a = eval_expr(it, toks, n, idx);
        Value out = v_none();
        if (is_list_word(a)) {
            char **lt = NULL;
            int ln = 0;
            list_to_items(a, &lt, &ln);
            if (ln == 0) {
                fprintf(stderr, "error: empty list\n");
                it->had_error = true;
            } else out = v_word(!strcmp(t, "first") ? lt[0] : lt[ln - 1]);
            free_tokens(lt, ln);
        } else {
            char *txt = value_to_text(a);
            size_t len = strlen(txt);
            if (len == 0) {
                fprintf(stderr, "error: empty word\n");
                it->had_error = true;
            } else {
                char ch[2] = {(!strcmp(t, "first") ? txt[0] : txt[len - 1]), '\0'};
                out = v_word(ch);
            }
            free(txt);
        }
        v_free(&a);
        return out;
    }
    if (!strcmp(t, "butfirst") || !strcmp(t, "butFirst") || !strcmp(t, "butlast") || !strcmp(t, "butLast") || !strcmp(t, "reverseList") || !strcmp(t, "reverse")) {
        Value a = eval_expr(it, toks, n, idx);
        Value out = v_none();
        if (is_list_word(a)) {
            char **lt = NULL;
            int ln = 0;
            list_to_items(a, &lt, &ln);
            if (!strcmp(t, "reverseList") || !strcmp(t, "reverse")) {
                for (int i = 0; i < ln / 2; i++) {
                    char *tmp = lt[i];
                    lt[i] = lt[ln - 1 - i];
                    lt[ln - 1 - i] = tmp;
                }
            } else if (ln > 0) {
                if (!strcmp(t, "butfirst") || !strcmp(t, "butFirst")) { free(lt[0]); for (int i = 1; i < ln; i++) lt[i - 1] = lt[i]; ln--; }
                else { free(lt[ln - 1]); ln--; }
            }
            char *joined = join_tokens_as_list(lt, ln);
            out = v_word(joined);
            free(joined);
            free_tokens(lt, ln);
        } else {
            char *txt = value_to_text(a);
            size_t len = strlen(txt);
            if (!strcmp(t, "reverseList") || !strcmp(t, "reverse")) {
                for (size_t i = 0; i < len / 2; i++) {
                    char c = txt[i];
                    txt[i] = txt[len - 1 - i];
                    txt[len - 1 - i] = c;
                }
                out = v_word(txt);
            } else {
                if (len == 0) out = v_word("");
                else if (!strcmp(t, "butfirst") || !strcmp(t, "butFirst")) out = v_word(txt + 1);
                else {
                    txt[len - 1] = '\0';
                    out = v_word(txt);
                }
            }
            free(txt);
        }
        v_free(&a);
        return out;
    }
    if (!strcmp(t, "item")) {
        Value indexv = eval_expr(it, toks, n, idx), src = eval_expr(it, toks, n, idx);
        int item = (int)to_num(indexv) - 1;
        Value out = v_none();
        if (is_list_word(src)) {
            char **lt = NULL;
            int ln = 0;
            list_to_items(src, &lt, &ln);
            if (item >= 0 && item < ln) out = v_word(lt[item]);
            else { fprintf(stderr, "error: item out of range\n"); it->had_error = true; }
            free_tokens(lt, ln);
        } else {
            char *txt = value_to_text(src);
            int len = (int)strlen(txt);
            if (item >= 0 && item < len) {
                char ch[2] = {txt[item], '\0'};
                out = v_word(ch);
            } else { fprintf(stderr, "error: item out of range\n"); it->had_error = true; }
            free(txt);
        }
        v_free(&indexv); v_free(&src);
        return out;
    }
    if (!strcmp(t, "word") || !strcmp(t, "list") || !strcmp(t, "sentence") ||
        !strcmp(t, "firstPut") || !strcmp(t, "firstput") || !strcmp(t, "fput") ||
        !strcmp(t, "lastPut") || !strcmp(t, "lastput") || !strcmp(t, "lput")) {
        Value a = eval_expr(it, toks, n, idx), b = eval_expr(it, toks, n, idx);
        Value out = v_none();
        if (!strcmp(t, "word")) {
            char *at = value_to_text(a), *bt = value_to_text(b);
            size_t need = strlen(at) + strlen(bt) + 1;
            char *joined = (char *)malloc(need);
            if (!joined) { fprintf(stderr, "out of memory\n"); exit(1); }
            snprintf(joined, need, "%s%s", at, bt);
            out = v_word(joined);
            free(joined);
            free(at); free(bt);
        } else {
            char **out_toks = NULL;
            int out_n = 0;
            if (!strcmp(t, "list")) {
                out_toks = (char **)calloc(2, sizeof(char *));
                if (!out_toks) { fprintf(stderr, "out of memory\n"); exit(1); }
                out_toks[0] = value_to_text(a);
                out_toks[1] = value_to_text(b);
                out_n = 2;
            } else {
                char **ta = NULL, **tb = NULL;
                int na = 0, nb = 0;
                if (is_list_word(a)) list_to_items(a, &ta, &na);
                else { ta = (char **)calloc(1, sizeof(char *)); ta[0] = value_to_text(a); na = 1; }
                if (is_list_word(b)) list_to_items(b, &tb, &nb);
                else { tb = (char **)calloc(1, sizeof(char *)); tb[0] = value_to_text(b); nb = 1; }
                out_n = na + nb;
                out_toks = (char **)calloc((size_t)out_n, sizeof(char *));
                if (!out_toks) { fprintf(stderr, "out of memory\n"); exit(1); }
                if (!strcmp(t, "firstPut") || !strcmp(t, "firstput") || !strcmp(t, "fput")) {
                    for (int i = 0; i < nb; i++) out_toks[i] = dupstr(tb[i]);
                    for (int i = 0; i < na; i++) out_toks[nb + i] = dupstr(ta[i]);
                } else {
                    for (int i = 0; i < na; i++) out_toks[i] = dupstr(ta[i]);
                    for (int i = 0; i < nb; i++) out_toks[na + i] = dupstr(tb[i]);
                }
                free_tokens(ta, na);
                free_tokens(tb, nb);
            }
            char *joined = join_tokens_as_list(out_toks, out_n);
            out = v_word(joined);
            free(joined);
            free_tokens(out_toks, out_n);
        }
        v_free(&a); v_free(&b);
        return out;
    }
    if (!strcmp(t, "memberp")) {
        Value needle = eval_expr(it, toks, n, idx), src = eval_expr(it, toks, n, idx);
        char *ntext = value_to_text(needle);
        bool found = false;
        if (is_list_word(src)) {
            char **lt = NULL;
            int ln = 0;
            list_to_items(src, &lt, &ln);
            for (int i = 0; i < ln; i++) if (!strcmp(lt[i], ntext)) { found = true; break; }
            free_tokens(lt, ln);
        } else {
            char *stext = value_to_text(src);
            found = strstr(stext, ntext) != NULL;
            free(stext);
        }
        free(ntext);
        v_free(&needle); v_free(&src);
        return v_num(found ? 1 : 0);
    }
    if (!strcmp(t, "propList")) {
        Value namev = eval_expr(it, toks, n, idx);
        char *name = value_to_text(namev);
        int count = 0;
        for (Prop *p = it->props; p; p = p->next) if (!strcmp(p->name, name)) count++;
        char **items = (char **)calloc((size_t)(count > 0 ? count : 1), sizeof(char *));
        if (!items) { fprintf(stderr, "out of memory\n"); exit(1); }
        int i = 0;
        for (Prop *p = it->props; p; p = p->next) if (!strcmp(p->name, name)) items[i++] = dupstr(p->prop);
        char *joined = join_tokens_as_list(items, i);
        Value out = v_word(joined);
        free(joined);
        free_tokens(items, i);
        free(name);
        v_free(&namev);
        return out;
    }
    if (!strcmp(t, "getProp") || !strcmp(t, "gProp")) {
        Value namev = eval_expr(it, toks, n, idx), propv = eval_expr(it, toks, n, idx);
        char *name = value_to_text(namev), *prop = value_to_text(propv);
        Prop *found = find_prop(it, name, prop);
        Value out = found ? v_copy(found->value) : v_none();
        free(name); free(prop);
        v_free(&namev); v_free(&propv);
        return out;
    }

    Proc *p = find_proc(it, t);
    if (p) {
        Value *args = (Value *)calloc((size_t)p->param_count, sizeof(*args));
        if (!args) { fprintf(stderr, "out of memory\n"); exit(1); }
        for (int i = 0; i < p->param_count; i++) args[i] = eval_expr(it, toks, n, idx);
        Value out = invoke_proc(it, p, args);
        for (int i = 0; i < p->param_count; i++) v_free(&args[i]);
        free(args);
        return out;
    }

    return v_word(t);
}

static bool exec_tokens(Interp *it, char **toks, int n, int *idx) {
    while (*idx < n) {
        char *cmd = toks[*idx];
        if (!strcmp(cmd, "]")) { fprintf(stderr, "error: unexpected ']'\n"); it->had_error = true; return false; }
        (*idx)++;

        if (!strcmp(cmd, "print") || !strcmp(cmd, "show")) {
            Value v = eval_expr(it, toks, n, idx);
            print_value(v);
            v_free(&v);
            continue;
        }
        if (!strcmp(cmd, "type")) {
            Value v = eval_expr(it, toks, n, idx);
            char *txt = value_to_text(v);
            fputs(txt, stdout);
            fflush(stdout);
            free(txt);
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
        if (!strcmp(cmd, "local")) {
            Value names = eval_expr(it, toks, n, idx);
            if (is_list_word(names)) {
                char **lt = NULL;
                int ln = 0;
                list_to_items(names, &lt, &ln);
                for (int li = 0; li < ln; li++) set_local_var(it->current_scope, lt[li], v_none());
                free_tokens(lt, ln);
            } else {
                char *name = value_to_text(names);
                set_local_var(it->current_scope, name, v_none());
                free(name);
            }
            v_free(&names);
            continue;
        }
        if (!strcmp(cmd, "localmake")) {
            if (*idx >= n) { fprintf(stderr, "error: localmake requires name\n"); it->had_error = true; return false; }
            char *name_tok = toks[(*idx)++];
            const char *name = name_tok[0] == '"' ? name_tok + 1 : name_tok;
            Value v = eval_expr(it, toks, n, idx);
            set_local_var(it->current_scope, name, v);
            v_free(&v);
            continue;
        }
        if (!strcmp(cmd, "repeat")) {
            Value c = eval_expr(it, toks, n, idx);
            int times = (int)to_num(c);
            v_free(&c);
            if (*idx >= n || strcmp(toks[*idx], "[")) { fprintf(stderr, "error: repeat requires [ ... ]\n"); it->had_error = true; return false; }
            int open = *idx;
            int close = find_close_bracket(toks, n, open);
            if (close < 0) { fprintf(stderr, "error: unmatched '['\n"); it->had_error = true; return false; }
            for (int r = 0; r < times && !it->stop && !it->has_output; r++) {
                int inner = open + 1;
                if (!exec_tokens(it, toks, close, &inner)) return false;
            }
            *idx = close + 1;
            continue;
        }
        if (!strcmp(cmd, "if") || !strcmp(cmd, "ifelse")) {
            Value c = eval_expr(it, toks, n, idx);
            bool cond = to_num(c) != 0;
            v_free(&c);
            if (*idx >= n || strcmp(toks[*idx], "[")) { fprintf(stderr, "error: if requires [ ... ]\n"); it->had_error = true; return false; }
            int t_open = *idx, t_close = find_close_bracket(toks, n, t_open);
            if (t_close < 0) { fprintf(stderr, "error: unmatched '['\n"); it->had_error = true; return false; }
            int f_open = t_close + 1, f_close = -1;
            if (!strcmp(cmd, "ifelse")) {
                if (f_open >= n || strcmp(toks[f_open], "[")) { fprintf(stderr, "error: ifelse requires second [ ... ]\n"); it->had_error = true; return false; }
                f_close = find_close_bracket(toks, n, f_open);
                if (f_close < 0) { fprintf(stderr, "error: unmatched '['\n"); it->had_error = true; return false; }
            }
            if (cond) {
                int inner = t_open + 1;
                if (!exec_tokens(it, toks, t_close, &inner)) return false;
            } else if (!strcmp(cmd, "ifelse")) {
                int inner = f_open + 1;
                if (!exec_tokens(it, toks, f_close, &inner)) return false;
            }
            *idx = (!strcmp(cmd, "ifelse")) ? (f_close + 1) : (t_close + 1);
            continue;
        }
        if (!strcmp(cmd, "run")) {
            Value list = eval_expr(it, toks, n, idx);
            if (!is_list_word(list)) {
                fprintf(stderr, "error: run requires list\n");
                it->had_error = true;
                v_free(&list);
                return false;
            }
            char **inner_toks = NULL;
            int inner_n = 0;
            list_to_items(list, &inner_toks, &inner_n);
            int inner_i = 0;
            bool ok = exec_tokens(it, inner_toks, inner_n, &inner_i);
            free_tokens(inner_toks, inner_n);
            v_free(&list);
            if (!ok) return false;
            continue;
        }
        if (!strcmp(cmd, "catch")) {
            Value label = eval_expr(it, toks, n, idx);
            Value list = eval_expr(it, toks, n, idx);
            v_free(&label);
            if (!is_list_word(list)) {
                fprintf(stderr, "error: catch requires list\n");
                it->had_error = true;
                v_free(&list);
                return false;
            }
            char **inner_toks = NULL;
            int inner_n = 0;
            list_to_items(list, &inner_toks, &inner_n);
            int inner_i = 0;
            bool ok = exec_tokens(it, inner_toks, inner_n, &inner_i);
            free_tokens(inner_toks, inner_n);
            v_free(&list);
            if (!ok) return false;
            continue;
        }
        if (!strcmp(cmd, "throw")) {
            Value err = eval_expr(it, toks, n, idx);
            char *txt = value_to_text(err);
            fprintf(stderr, "error: %s\n", txt);
            free(txt);
            v_free(&err);
            it->had_error = true;
            return false;
        }
        if (!strcmp(cmd, "output")) {
            v_free(&it->output);
            it->output = eval_expr(it, toks, n, idx);
            it->has_output = true;
            return true;
        }
        if (!strcmp(cmd, "op")) {
            v_free(&it->output);
            it->output = eval_expr(it, toks, n, idx);
            it->has_output = true;
            return true;
        }
        if (!strcmp(cmd, "stop")) {
            it->stop = true;
            return true;
        }
        if (!strcmp(cmd, "wait")) {
            Value t = eval_expr(it, toks, n, idx);
            double ticks = to_num(t);
            v_free(&t);
            if (ticks > 0) {
                useconds_t us = (useconds_t)(ticks * (1000000.0 / 60.0));
                usleep(us);
            }
            continue;
        }
        if (!strcmp(cmd, "putProp") || !strcmp(cmd, "pProp")) {
            Value nname = eval_expr(it, toks, n, idx);
            Value pprop = eval_expr(it, toks, n, idx);
            Value v = eval_expr(it, toks, n, idx);
            char *name = value_to_text(nname), *prop = value_to_text(pprop);
            put_prop(it, name, prop, v);
            free(name); free(prop);
            v_free(&nname); v_free(&pprop); v_free(&v);
            continue;
        }
        if (!strcmp(cmd, "remProp")) {
            Value nname = eval_expr(it, toks, n, idx);
            Value pprop = eval_expr(it, toks, n, idx);
            char *name = value_to_text(nname), *prop = value_to_text(pprop);
            remove_prop(it, name, prop);
            free(name); free(prop);
            v_free(&nname); v_free(&pprop);
            continue;
        }
        if (!strcmp(cmd, "define")) {
            Value nname = eval_expr(it, toks, n, idx);
            Value params = eval_expr(it, toks, n, idx);
            Value body = eval_expr(it, toks, n, idx);
            if (!is_list_word(params) || !is_list_word(body)) {
                fprintf(stderr, "error: define requires parameter and body lists\n");
                it->had_error = true;
                v_free(&nname); v_free(&params); v_free(&body);
                return false;
            }
            char *name = value_to_text(nname);
            char **pt = NULL, **bt = NULL;
            int pn = 0, bn = 0;
            list_to_items(params, &pt, &pn);
            list_to_items(body, &bt, &bn);

            Proc *np = (Proc *)calloc(1, sizeof(*np));
            if (!np) { fprintf(stderr, "out of memory\n"); exit(1); }
            np->name = dupstr(name);
            np->param_count = pn;
            np->params = (char **)calloc((size_t)pn, sizeof(char *));
            if (!np->params && pn > 0) { fprintf(stderr, "out of memory\n"); exit(1); }
            for (int pi = 0; pi < pn; pi++) {
                const char *raw = pt[pi];
                np->params[pi] = dupstr(raw[0] == ':' ? raw + 1 : raw);
            }
            np->body = tokens_to_text(bt, 0, bn);
            set_proc(it, np);

            free(name);
            free_tokens(pt, pn);
            free_tokens(bt, bn);
            v_free(&nname); v_free(&params); v_free(&body);
            continue;
        }
        if (!strcmp(cmd, "words")) {
            static const char *builtins[] = {
                "print", "show", "type", "make", "local", "localmake", "repeat", "if", "ifelse", "run",
                "output", "op", "stop", "words", "sum", "difference", "product", "quotient",
                "remainder", "power", "abs", "sqrt", "exp", "log", "log10", "sin", "cos", "tan",
                "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh", "integer", "round", "random",
                "pi", "lessp", "greaterp", "equalp", "and", "or", "not",
                "thing", "namep", "definep", "numberp", "wordp", "listp", "emptyp", "ascii", "char",
                "uppercase", "lowercase", "count", "first", "last", "butfirst", "butlast", "item",
                "word", "list", "sentence", "firstPut", "lastPut", "memberp",
                "getProp", "gProp", "propList", "putProp", "pProp", "remProp",
                "define", "catch", "throw", "date", "time", "wait", "readWord", "readChar", "readChars", "readList"
            };
            for (Proc *p = it->procs; p; p = p->next) printf("%s ", p->name);
            for (size_t wi = 0; wi < sizeof(builtins) / sizeof(*builtins); wi++) printf("%s ", builtins[wi]);
            printf("\n");
            continue;
        }
        if (!strcmp(cmd, "date")) {
            time_t now = time(NULL);
            struct tm tmv;
            localtime_r(&now, &tmv);
            char out[32];
            strftime(out, sizeof(out), "%Y-%m-%d", &tmv);
            printf("%s\n", out);
            continue;
        }
        if (!strcmp(cmd, "time")) {
            time_t now = time(NULL);
            struct tm tmv;
            localtime_r(&now, &tmv);
            char out[32];
            strftime(out, sizeof(out), "%H:%M:%S", &tmv);
            printf("%s\n", out);
            continue;
        }
        if (!strcmp(cmd, "readWord")) {
            char buf[MAX_LINE_LENGTH];
            if (scanf("%8191s", buf) == 1) printf("%s\n", buf);
            continue;
        }
        if (!strcmp(cmd, "readChar")) {
            int c = getchar();
            if (c != EOF) printf("%c\n", c);
            continue;
        }
        if (!strcmp(cmd, "readChars")) {
            Value nread = eval_expr(it, toks, n, idx);
            int count = (int)to_num(nread);
            v_free(&nread);
            if (count < 0) count = 0;
            char *buf = (char *)calloc((size_t)count + 1, 1);
            if (!buf) { fprintf(stderr, "out of memory\n"); exit(1); }
            int got = (int)fread(buf, 1, (size_t)count, stdin);
            buf[got] = '\0';
            printf("%s\n", buf);
            free(buf);
            continue;
        }
        if (!strcmp(cmd, "readList")) {
            char line[MAX_LINE_LENGTH];
            if (fgets(line, sizeof(line), stdin)) {
                size_t len = strlen(line);
                while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r')) line[--len] = '\0';
                char **lt = NULL;
                int ln = 0;
                tokenize(line, &lt, &ln);
                char *joined = join_tokens_as_list(lt, ln);
                printf("%s\n", joined);
                free(joined);
                free_tokens(lt, ln);
            }
            continue;
        }

        Proc *p = find_proc(it, cmd);
        if (!p) { fprintf(stderr, "error: unknown command '%s'\n", cmd); it->had_error = true; return false; }
        Value *args = (Value *)calloc((size_t)p->param_count, sizeof(*args));
        if (!args) { fprintf(stderr, "out of memory\n"); exit(1); }
        for (int i = 0; i < p->param_count; i++) args[i] = eval_expr(it, toks, n, idx);
        Value r = invoke_proc(it, p, args);
        v_free(&r);
        for (int i = 0; i < p->param_count; i++) v_free(&args[i]);
        free(args);
        if (it->stop || it->has_output) return true;
    }
    return true;
}

static void builder_reset(ProcBuilder *b) {
    b->active = false;
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

static void start_proc(Interp *it, char **toks, int n) {
    if (n < 2) { fprintf(stderr, "error: to requires a name\n"); it->had_error = true; return; }
    builder_reset(&it->builder);
    it->builder.active = true;
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
    if (!strcmp(toks[0], "to")) { start_proc(it, toks, n); free_tokens(toks, n); return; }
    int i = 0;
    exec_tokens(it, toks, n, &i);
    free_tokens(toks, n);
}

static void interp_init(Interp *it) {
    memset(it, 0, sizeof(*it));
    it->global_scope = scope_new(NULL);
    it->current_scope = it->global_scope;
    it->output = v_none();
    srand((unsigned int)time(NULL));
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
    while (it->props) {
        Prop *next = it->props->next;
        free(it->props->name);
        free(it->props->prop);
        v_free(&it->props->value);
        free(it->props);
        it->props = next;
    }
    v_free(&it->output);
}

static void run_stream(Interp *it, FILE *f) {
    char line[MAX_LINE_LENGTH];
    bool interactive = (f == stdin) && isatty(STDIN_FILENO);
    while (1) {
#ifdef HAVE_READLINE
        if (interactive) {
            char *rl = readline("> ");
            if (!rl) break;
            size_t len = strlen(rl);
            if (len >= MAX_LINE_LENGTH) {
                fprintf(stderr, "error: input line too long (max %d bytes)\n", MAX_LINE_LENGTH - 1);
                it->had_error = true;
                free(rl);
                continue;
            }
            if (*rl) add_history(rl);
            memcpy(line, rl, len + 1);
            free(rl);
        } else
#endif
        {
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
        }
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

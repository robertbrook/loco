#include <ctype.h>
#include <stdbool.h>
#include <math.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/select.h>
#include <time.h>

#define MAX_LINE_LENGTH 8192
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

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

static bool str_ieq(const char *a, const char *b) {
    while (*a && *b) {
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) return false;
        a++;
        b++;
    }
    return *a == '\0' && *b == '\0';
}

static int uniform_random_int(int limit) {
    if (limit <= 0) return 0;
    unsigned int lim = (unsigned int)limit;
    unsigned int max_acceptable = (unsigned int)RAND_MAX - ((unsigned int)RAND_MAX % lim);
    unsigned int r = 0;
    do {
        r = (unsigned int)rand();
    } while (r >= max_acceptable);
    return (int)(r % lim);
}

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

static bool to_bool(Value v) { return to_num(v) != 0; }

static bool is_list_literal(const char *s) {
    size_t n = strlen(s);
    return n >= 2 && s[0] == '[' && s[n - 1] == ']';
}

static char *value_to_string(Value v) {
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

static char *list_inner_copy(const char *s) {
    if (!is_list_literal(s)) return dupstr(s ? s : "");
    size_t n = strlen(s);
    if (n <= 2) return dupstr("");
    char *out = (char *)malloc(n - 1);
    if (!out) { fprintf(stderr, "out of memory\n"); exit(1); }
    memcpy(out, s + 1, n - 2);
    out[n - 2] = '\0';
    return out;
}

static char *list_from_inner(const char *inner) {
    size_t n = strlen(inner);
    char *out = (char *)malloc(n + 3);
    if (!out) { fprintf(stderr, "out of memory\n"); exit(1); }
    out[0] = '[';
    memcpy(out + 1, inner, n);
    out[n + 1] = ']';
    out[n + 2] = '\0';
    return out;
}

static char **split_list_elements(const char *list, int *count_out) {
    char *inner = list_inner_copy(list);
    int cap = 8, count = 0;
    char **items = (char **)malloc((size_t)cap * sizeof(*items));
    if (!items) { fprintf(stderr, "out of memory\n"); exit(1); }
    const char *p = inner;
    while (*p) {
        while (*p && isspace((unsigned char)*p)) p++;
        if (!*p) break;
        const char *start = p;
        int depth = 0;
        while (*p) {
            if (*p == '[') depth++;
            else if (*p == ']') depth--;
            if (depth == 0 && isspace((unsigned char)*p)) break;
            p++;
        }
        size_t len = (size_t)(p - start);
        char *item = (char *)malloc(len + 1);
        if (!item) { fprintf(stderr, "out of memory\n"); exit(1); }
        memcpy(item, start, len);
        item[len] = '\0';
        if (count == cap) {
            cap *= 2;
            items = (char **)realloc(items, (size_t)cap * sizeof(*items));
            if (!items) { fprintf(stderr, "out of memory\n"); exit(1); }
        }
        items[count++] = item;
    }
    free(inner);
    *count_out = count;
    return items;
}

static void free_list_elements(char **items, int count) {
    for (int i = 0; i < count; i++) free(items[i]);
    free(items);
}

static char *list_concat_items(char **left_items, int left_n, char **right_items, int right_n) {
    size_t total = 0;
    for (int i = 0; i < left_n; i++) total += strlen(left_items[i]) + 1;
    for (int i = 0; i < right_n; i++) total += strlen(right_items[i]) + 1;
    char *inner = (char *)malloc(total + 1);
    if (!inner) { fprintf(stderr, "out of memory\n"); exit(1); }
    inner[0] = '\0';
    bool first = true;
    for (int i = 0; i < left_n; i++) {
        if (!first) strcat(inner, " ");
        strcat(inner, left_items[i]);
        first = false;
    }
    for (int i = 0; i < right_n; i++) {
        if (!first) strcat(inner, " ");
        strcat(inner, right_items[i]);
        first = false;
    }
    return inner;
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
    for (Var *v = s->vars; v; v = v->next) if (str_ieq(v->name, name)) return v;
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
    for (Proc *p = it->procs; p; p = p->next) if (str_ieq(p->name, name)) return p;
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
        if (str_ieq(p->name, np->name)) {
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

    if (!strcmp(t, "[")) {
        int open = *idx - 1;
        int close = find_close_bracket(toks, n, open);
        if (close < 0) {
            fprintf(stderr, "error: unmatched '['\n");
            it->had_error = true;
            return v_none();
        }
        size_t needed = 1;
        for (int i = open + 1; i < close; i++) needed += strlen(toks[i]) + 1;
        char *inner = (char *)malloc(needed);
        if (!inner) { fprintf(stderr, "out of memory\n"); exit(1); }
        inner[0] = '\0';
        bool first = true;
        for (int i = open + 1; i < close; i++) {
            if (!first) strcat(inner, " ");
            strcat(inner, toks[i]);
            first = false;
        }
        char *list = list_from_inner(inner);
        free(inner);
        *idx = close + 1;
        Value out = v_word(list);
        free(list);
        return out;
    }
    if (t[0] == '"') return v_word(t + 1);
    if (t[0] == ':') {
        Var *v = find_var(it->current_scope, t + 1);
        if (!v) { fprintf(stderr, "error: unknown variable '%s'\n", t + 1); it->had_error = true; return v_none(); }
        return v_copy(v->value);
    }
    double num = 0;
    if (parse_num(t, &num)) return v_num(num);

    if (str_ieq(t, "sum") || str_ieq(t, "difference") || str_ieq(t, "product") || str_ieq(t, "quotient") || str_ieq(t, "remainder") || str_ieq(t, "modulo") || str_ieq(t, "power")) {
        Value a = eval_expr(it, toks, n, idx), b = eval_expr(it, toks, n, idx);
        double av = to_num(a), bv = to_num(b), out = 0;
        if (str_ieq(t, "sum")) out = av + bv;
        if (str_ieq(t, "difference")) out = av - bv;
        if (str_ieq(t, "product")) out = av * bv;
        if (str_ieq(t, "quotient")) {
            if (bv == 0) {
                fprintf(stderr, "error: division by zero\n");
                it->had_error = true;
                out = 0;
            } else {
                out = av / bv;
            }
        }
        if (str_ieq(t, "remainder") || str_ieq(t, "modulo")) {
            if (bv == 0) {
                fprintf(stderr, "error: division by zero\n");
                it->had_error = true;
                out = 0;
            } else {
                out = fmod(av, bv);
            }
        }
        if (str_ieq(t, "power")) out = pow(av, bv);
        v_free(&a); v_free(&b);
        return v_num(out);
    }
    if (str_ieq(t, "minus") || str_ieq(t, "abs") || str_ieq(t, "int") || str_ieq(t, "round") ||
        str_ieq(t, "sqrt") || str_ieq(t, "exp") || str_ieq(t, "ln") || str_ieq(t, "log10") ||
        str_ieq(t, "sin") || str_ieq(t, "cos") || str_ieq(t, "tan") ||
        str_ieq(t, "arcsin") || str_ieq(t, "arccos") || str_ieq(t, "arctan") || str_ieq(t, "random")) {
        Value a = eval_expr(it, toks, n, idx);
        double av = to_num(a), out = 0;
        if (str_ieq(t, "minus")) out = -av;
        if (str_ieq(t, "abs")) out = fabs(av);
        if (str_ieq(t, "int")) out = floor(av);
        if (str_ieq(t, "round")) out = round(av);
        if (str_ieq(t, "sqrt")) {
            if (av < 0) {
                fprintf(stderr, "error: sqrt of negative number\n");
                it->had_error = true;
                out = 0;
            } else out = sqrt(av);
        }
        if (str_ieq(t, "exp")) out = exp(av);
        if (str_ieq(t, "ln")) {
            if (av <= 0) {
                fprintf(stderr, "error: ln input must be positive\n");
                it->had_error = true;
                out = 0;
            } else out = log(av);
        }
        if (str_ieq(t, "log10")) {
            if (av <= 0) {
                fprintf(stderr, "error: log10 input must be positive\n");
                it->had_error = true;
                out = 0;
            } else out = log10(av);
        }
        if (str_ieq(t, "sin")) out = sin(av * M_PI / 180.0);
        if (str_ieq(t, "cos")) out = cos(av * M_PI / 180.0);
        if (str_ieq(t, "tan")) out = tan(av * M_PI / 180.0);
        if (str_ieq(t, "arcsin")) {
            if (av < -1 || av > 1) {
                fprintf(stderr, "error: arcsin input out of range\n");
                it->had_error = true;
                out = 0;
            } else out = asin(av) * 180.0 / M_PI;
        }
        if (str_ieq(t, "arccos")) {
            if (av < -1 || av > 1) {
                fprintf(stderr, "error: arccos input out of range\n");
                it->had_error = true;
                out = 0;
            } else out = acos(av) * 180.0 / M_PI;
        }
        if (str_ieq(t, "arctan")) out = atan(av) * 180.0 / M_PI;
        if (str_ieq(t, "random")) {
            int limit = (int)av;
            out = (double)uniform_random_int(limit);
        }
        v_free(&a);
        return v_num(out);
    }
    if (str_ieq(t, "arctan2")) {
        Value a = eval_expr(it, toks, n, idx), b = eval_expr(it, toks, n, idx);
        double out = atan2(to_num(a), to_num(b)) * 180.0 / M_PI;
        v_free(&a); v_free(&b);
        return v_num(out);
    }
    if (str_ieq(t, "lessp") || str_ieq(t, "less?") || str_ieq(t, "greaterp") || str_ieq(t, "greater?") || str_ieq(t, "equalp") || str_ieq(t, "equal?")) {
        Value a = eval_expr(it, toks, n, idx), b = eval_expr(it, toks, n, idx);
        double out = 0;
        if (str_ieq(t, "lessp") || str_ieq(t, "less?")) out = to_num(a) < to_num(b);
        if (str_ieq(t, "greaterp") || str_ieq(t, "greater?")) out = to_num(a) > to_num(b);
        if (str_ieq(t, "equalp") || str_ieq(t, "equal?")) {
            if (a.type == VAL_WORD || b.type == VAL_WORD) {
                const char *aw = (a.type == VAL_WORD && a.word) ? a.word : "";
                const char *bw = (b.type == VAL_WORD && b.word) ? b.word : "";
                out = str_ieq(aw, bw);
            } else out = to_num(a) == to_num(b);
        }
        v_free(&a); v_free(&b);
        return v_num(out);
    }
    if (str_ieq(t, "and") || str_ieq(t, "or")) {
        Value a = eval_expr(it, toks, n, idx), b = eval_expr(it, toks, n, idx);
        double out = str_ieq(t, "and") ? (to_bool(a) && to_bool(b)) : (to_bool(a) || to_bool(b));
        v_free(&a); v_free(&b);
        return v_num(out);
    }
    if (str_ieq(t, "not")) {
        Value a = eval_expr(it, toks, n, idx);
        double out = !to_bool(a);
        v_free(&a);
        return v_num(out);
    }
    if (str_ieq(t, "thing")) {
        Value name = eval_expr(it, toks, n, idx);
        const char *var = (name.type == VAL_WORD && name.word) ? name.word : "";
        Var *v = find_var(it->current_scope, var);
        Value out = v ? v_copy(v->value) : v_none();
        if (!v) { fprintf(stderr, "error: unknown variable '%s'\n", var); it->had_error = true; }
        v_free(&name);
        return out;
    }
    if (str_ieq(t, "word")) {
        Value a = eval_expr(it, toks, n, idx), b = eval_expr(it, toks, n, idx);
        char *as = value_to_string(a), *bs = value_to_string(b);
        size_t nout = strlen(as) + strlen(bs) + 1;
        char *out = (char *)malloc(nout);
        if (!out) { fprintf(stderr, "out of memory\n"); exit(1); }
        strcpy(out, as);
        strcat(out, bs);
        Value r = v_word(out);
        free(out); free(as); free(bs);
        v_free(&a); v_free(&b);
        return r;
    }
    if (str_ieq(t, "list")) {
        Value a = eval_expr(it, toks, n, idx), b = eval_expr(it, toks, n, idx);
        char *as = value_to_string(a), *bs = value_to_string(b);
        size_t inner_len = strlen(as) + strlen(bs) + 2;
        char *inner = (char *)malloc(inner_len);
        if (!inner) { fprintf(stderr, "out of memory\n"); exit(1); }
        snprintf(inner, inner_len, "%s %s", as, bs);
        char *ls = list_from_inner(inner);
        Value r = v_word(ls);
        free(ls); free(inner); free(as); free(bs);
        v_free(&a); v_free(&b);
        return r;
    }
    if (str_ieq(t, "sentence") || str_ieq(t, "se")) {
        Value a = eval_expr(it, toks, n, idx), b = eval_expr(it, toks, n, idx);
        char *as = value_to_string(a), *bs = value_to_string(b);
        int an = 0, bn = 0;
        char **ai = is_list_literal(as) ? split_list_elements(as, &an) : NULL;
        char **bi = is_list_literal(bs) ? split_list_elements(bs, &bn) : NULL;
        if (!is_list_literal(as)) {
            ai = (char **)malloc(sizeof(char *));
            if (!ai) { fprintf(stderr, "out of memory\n"); exit(1); }
            ai[0] = dupstr(as);
            an = 1;
        }
        if (!is_list_literal(bs)) {
            bi = (char **)malloc(sizeof(char *));
            if (!bi) { fprintf(stderr, "out of memory\n"); exit(1); }
            bi[0] = dupstr(bs);
            bn = 1;
        }
        char *inner = list_concat_items(ai, an, bi, bn);
        char *ls = list_from_inner(inner);
        Value r = v_word(ls);
        free(ls); free(inner);
        free_list_elements(ai, an); free_list_elements(bi, bn);
        free(as); free(bs);
        v_free(&a); v_free(&b);
        return r;
    }
    if (str_ieq(t, "fput") || str_ieq(t, "lput")) {
        Value item = eval_expr(it, toks, n, idx), lst = eval_expr(it, toks, n, idx);
        char *is = value_to_string(item), *ls = value_to_string(lst);
        int nitems = 0;
        char **items = split_list_elements(ls, &nitems);
        char *inner = NULL;
        size_t total = strlen(is) + 1;
        for (int i = 0; i < nitems; i++) total += strlen(items[i]) + 1;
        inner = (char *)malloc(total + 1);
        if (!inner) { fprintf(stderr, "out of memory\n"); exit(1); }
        inner[0] = '\0';
        bool first = true;
        if (str_ieq(t, "fput")) {
            strcat(inner, is);
            first = false;
        }
        for (int i = 0; i < nitems; i++) {
            if (!first) strcat(inner, " ");
            strcat(inner, items[i]);
            first = false;
        }
        if (str_ieq(t, "lput")) {
            if (!first) strcat(inner, " ");
            strcat(inner, is);
        }
        char *out_list = list_from_inner(inner);
        Value r = v_word(out_list);
        free(out_list); free(inner); free(is); free(ls);
        free_list_elements(items, nitems);
        v_free(&item); v_free(&lst);
        return r;
    }
    if (str_ieq(t, "first") || str_ieq(t, "last") || str_ieq(t, "butfirst") || str_ieq(t, "bf") ||
        str_ieq(t, "butlast") || str_ieq(t, "bl") || str_ieq(t, "count") || str_ieq(t, "item")) {
        Value x = eval_expr(it, toks, n, idx);
        Value y = v_none();
        if (str_ieq(t, "item")) {
            y = x;
            x = eval_expr(it, toks, n, idx);
        }
        char *xs = value_to_string(x);
        if (str_ieq(t, "count")) {
            if (is_list_literal(xs)) {
                int cn = 0;
                char **items = split_list_elements(xs, &cn);
                free_list_elements(items, cn);
                free(xs);
                if (str_ieq(t, "item")) v_free(&y);
                v_free(&x);
                return v_num(cn);
            }
            double out = (double)strlen(xs);
            free(xs);
            if (str_ieq(t, "item")) v_free(&y);
            v_free(&x);
            return v_num(out);
        }
        if (str_ieq(t, "item")) {
            int index = (int)to_num(y);
            if (is_list_literal(xs)) {
                int cn = 0;
                char **items = split_list_elements(xs, &cn);
                Value out = (index >= 1 && index <= cn) ? v_word(items[index - 1]) : v_none();
                free_list_elements(items, cn);
                free(xs);
                v_free(&y); v_free(&x);
                return out;
            }
            size_t len = strlen(xs);
            if (index < 1 || (size_t)index > len) {
                free(xs);
                v_free(&y); v_free(&x);
                return v_none();
            }
            char out_s[2] = {xs[index - 1], '\0'};
            Value out = v_word(out_s);
            free(xs);
            v_free(&y); v_free(&x);
            return out;
        }
        if (is_list_literal(xs)) {
            int cn = 0;
            char **items = split_list_elements(xs, &cn);
            Value out = v_none();
            if ((str_ieq(t, "first") || str_ieq(t, "last")) && cn > 0) {
                out = str_ieq(t, "first") ? v_word(items[0]) : v_word(items[cn - 1]);
            } else if (str_ieq(t, "butfirst") || str_ieq(t, "bf") || str_ieq(t, "butlast") || str_ieq(t, "bl")) {
                int start = (str_ieq(t, "butfirst") || str_ieq(t, "bf")) ? 1 : 0;
                int end = (str_ieq(t, "butlast") || str_ieq(t, "bl")) ? (cn - 1) : cn;
                if (end < start) end = start;
                size_t total = 1;
                for (int i = start; i < end; i++) total += strlen(items[i]) + 1;
                char *inner = (char *)malloc(total);
                if (!inner) { fprintf(stderr, "out of memory\n"); exit(1); }
                inner[0] = '\0';
                bool first = true;
                for (int i = start; i < end; i++) {
                    if (!first) strcat(inner, " ");
                    strcat(inner, items[i]);
                    first = false;
                }
                char *ls = list_from_inner(inner);
                out = v_word(ls);
                free(ls);
                free(inner);
            }
            free_list_elements(items, cn);
            free(xs);
            v_free(&x);
            return out;
        }
        size_t len = strlen(xs);
        Value out = v_none();
        if ((str_ieq(t, "first") || str_ieq(t, "last")) && len > 0) {
            char s[2] = {str_ieq(t, "first") ? xs[0] : xs[len - 1], '\0'};
            out = v_word(s);
        } else if ((str_ieq(t, "butfirst") || str_ieq(t, "bf") || str_ieq(t, "butlast") || str_ieq(t, "bl"))) {
            if (len == 0) out = v_word("");
            else {
                size_t start = (str_ieq(t, "butfirst") || str_ieq(t, "bf")) ? 1 : 0;
                size_t end = (str_ieq(t, "butlast") || str_ieq(t, "bl")) ? (len - 1) : len;
                if (end < start) end = start;
                char *s = (char *)malloc(end - start + 1);
                if (!s) { fprintf(stderr, "out of memory\n"); exit(1); }
                memcpy(s, xs + start, end - start);
                s[end - start] = '\0';
                out = v_word(s);
                free(s);
            }
        }
        free(xs);
        v_free(&x);
        return out;
    }
    if (str_ieq(t, "emptyp") || str_ieq(t, "empty?") || str_ieq(t, "wordp") || str_ieq(t, "word?") ||
        str_ieq(t, "listp") || str_ieq(t, "list?") || str_ieq(t, "numberp") || str_ieq(t, "number?") ||
        str_ieq(t, "memberp") || str_ieq(t, "member?")) {
        Value a = eval_expr(it, toks, n, idx);
        Value b = v_none();
        if (str_ieq(t, "memberp") || str_ieq(t, "member?")) b = eval_expr(it, toks, n, idx);
        double out = 0;
        if (str_ieq(t, "emptyp") || str_ieq(t, "empty?")) {
            char *s = value_to_string(a);
            if (is_list_literal(s)) {
                int cn = 0;
                char **items = split_list_elements(s, &cn);
                out = (cn == 0);
                free_list_elements(items, cn);
            } else out = s[0] == '\0';
            free(s);
        } else if (str_ieq(t, "wordp") || str_ieq(t, "word?")) {
            char *s = value_to_string(a);
            out = !is_list_literal(s);
            free(s);
        } else if (str_ieq(t, "listp") || str_ieq(t, "list?")) {
            char *s = value_to_string(a);
            out = is_list_literal(s);
            free(s);
        } else if (str_ieq(t, "numberp") || str_ieq(t, "number?")) {
            if (a.type == VAL_NUM) out = 1;
            else if (a.type == VAL_WORD && a.word) {
                double parsed = 0;
                out = parse_num(a.word, &parsed);
            } else out = 0;
        } else {
            char *needle = value_to_string(a), *hay = value_to_string(b);
            if (is_list_literal(hay)) {
                int cn = 0;
                char **items = split_list_elements(hay, &cn);
                for (int i = 0; i < cn; i++) if (str_ieq(items[i], needle)) { out = 1; break; }
                free_list_elements(items, cn);
            } else {
                out = str_ieq(hay, needle);
            }
            free(needle); free(hay);
        }
        v_free(&a); v_free(&b);
        return v_num(out);
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

        if (str_ieq(cmd, "print") || str_ieq(cmd, "pr") || str_ieq(cmd, "show")) {
            Value v = eval_expr(it, toks, n, idx);
            print_value(v);
            v_free(&v);
            continue;
        }
        if (str_ieq(cmd, "type")) {
            Value v = eval_expr(it, toks, n, idx);
            if (v.type == VAL_NUM) {
                long long integer_part = (long long)v.num;
                if ((double)integer_part == v.num) printf("%lld", integer_part);
                else printf("%g", v.num);
            } else if (v.type == VAL_WORD && v.word) {
                printf("%s", v.word);
            }
            fflush(stdout);
            v_free(&v);
            continue;
        }
        if (str_ieq(cmd, "make")) {
            if (*idx >= n) { fprintf(stderr, "error: make requires name\n"); it->had_error = true; return false; }
            char *name_tok = toks[(*idx)++];
            const char *name = name_tok[0] == '"' ? name_tok + 1 : name_tok;
            Value v = eval_expr(it, toks, n, idx);
            set_var(it->current_scope, name, v);
            v_free(&v);
            continue;
        }
        if (str_ieq(cmd, "wait")) {
            Value t = eval_expr(it, toks, n, idx);
            double tenths = to_num(t);
            if (tenths > 0) {
                double total_seconds = tenths / 10.0;
                struct timeval tv;
                tv.tv_sec = (long)total_seconds;
                tv.tv_usec = (long)((total_seconds - (double)tv.tv_sec) * 1000000.0);
                if (tv.tv_usec < 0) tv.tv_usec = 0;
                select(0, NULL, NULL, NULL, &tv);
            }
            v_free(&t);
            continue;
        }
        if (str_ieq(cmd, "run")) {
            Value list = eval_expr(it, toks, n, idx);
            char *ls = value_to_string(list);
            int cn = 0;
            char **items = split_list_elements(ls, &cn);
            int inner = 0;
            if (!exec_tokens(it, items, cn, &inner)) {
                free_list_elements(items, cn);
                free(ls);
                v_free(&list);
                return false;
            }
            free_list_elements(items, cn);
            free(ls);
            v_free(&list);
            continue;
        }
        if (str_ieq(cmd, "repeat")) {
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
        if (str_ieq(cmd, "if") || str_ieq(cmd, "ifelse")) {
            Value c = eval_expr(it, toks, n, idx);
            bool cond = to_num(c) != 0;
            v_free(&c);
            if (*idx >= n || strcmp(toks[*idx], "[")) { fprintf(stderr, "error: if requires [ ... ]\n"); it->had_error = true; return false; }
            int t_open = *idx, t_close = find_close_bracket(toks, n, t_open);
            if (t_close < 0) { fprintf(stderr, "error: unmatched '['\n"); it->had_error = true; return false; }
            int f_open = t_close + 1, f_close = -1;
            if (str_ieq(cmd, "ifelse")) {
                if (f_open >= n || strcmp(toks[f_open], "[")) { fprintf(stderr, "error: ifelse requires second [ ... ]\n"); it->had_error = true; return false; }
                f_close = find_close_bracket(toks, n, f_open);
                if (f_close < 0) { fprintf(stderr, "error: unmatched '['\n"); it->had_error = true; return false; }
            }
            if (cond) {
                int inner = t_open + 1;
                if (!exec_tokens(it, toks, t_close, &inner)) return false;
            } else if (str_ieq(cmd, "ifelse")) {
                int inner = f_open + 1;
                if (!exec_tokens(it, toks, f_close, &inner)) return false;
            }
            *idx = (str_ieq(cmd, "ifelse")) ? (f_close + 1) : (t_close + 1);
            continue;
        }
        if (str_ieq(cmd, "output") || str_ieq(cmd, "op")) {
            v_free(&it->output);
            it->output = eval_expr(it, toks, n, idx);
            it->has_output = true;
            return true;
        }
        if (str_ieq(cmd, "stop")) {
            it->stop = true;
            return true;
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
        if (str_ieq(toks[0], "end")) finish_proc(it);
        else builder_append(&it->builder, line);
        free_tokens(toks, n);
        return;
    }
    if (str_ieq(toks[0], "to")) { start_proc(it, toks, n); free_tokens(toks, n); return; }
    int i = 0;
    exec_tokens(it, toks, n, &i);
    free_tokens(toks, n);
}

static void interp_init(Interp *it) {
    memset(it, 0, sizeof(*it));
    srand((unsigned int)time(NULL));
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

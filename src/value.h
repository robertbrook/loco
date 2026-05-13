
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

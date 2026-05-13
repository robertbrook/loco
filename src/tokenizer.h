
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

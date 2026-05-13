CC = gcc
CFLAGS = -Wall -Wextra -std=c99 -g -I src -D_POSIX_C_SOURCE=200809L -Wno-unused-parameter
LDFLAGS = -lm

SRCS = src/main.c src/value.c src/gc.c src/tokenizer.c \
       src/env.c src/workspace.c src/interp.c \
       src/prim_data.c src/prim_arith.c src/prim_logic.c \
       src/prim_comm.c src/prim_file.c src/prim_ctrl.c \
       src/prim_ws.c src/prim_tmpl.c

OBJS = $(SRCS:.c=.o)

loco: $(OBJS)
	$(CC) $(CFLAGS) -o loco $(OBJS) $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

test: test/test_main.c $(filter-out src/main.o, $(OBJS))
	$(CC) $(CFLAGS) -o test/test_loco test/test_main.c \
	    $(filter-out src/main.o, $(OBJS)) $(LDFLAGS)
	./test/test_loco

clean:
	rm -f $(OBJS) loco test/test_loco

.PHONY: test clean

CC ?= cc
CFLAGS ?= -std=c11 -Wall -Wextra -Werror -O2
READLINE_CFLAGS := -DHAVE_READLINE
READLINE_LIBS := -lreadline

TARGET := loco

.PHONY: all test clean

all: $(TARGET)

$(TARGET): loco.c
	$(CC) $(CFLAGS) $(READLINE_CFLAGS) $< -o $@ $(READLINE_LIBS)

test: $(TARGET)
	sh tests/smoke.sh

clean:
	rm -f $(TARGET)

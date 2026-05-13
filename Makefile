CC ?= cc
CFLAGS ?= -std=c11 -Wall -Wextra -Werror -O2
MATH_LIBS := -lm

# Detect readline availability at build time
READLINE_CFLAGS := $(shell pkg-config --cflags readline 2>/dev/null || (echo | $(CC) -x c - -lreadline -o /dev/null 2>/dev/null && echo -DHAVE_READLINE) || true)
READLINE_LIBS   := $(shell pkg-config --libs readline 2>/dev/null || (echo | $(CC) -x c - -lreadline -o /dev/null 2>/dev/null && echo -lreadline) || true)

TARGET := loco

.PHONY: all test clean

all: $(TARGET)

$(TARGET): loco.c
	$(CC) $(CFLAGS) $(READLINE_CFLAGS) $< -o $@ $(READLINE_LIBS) $(MATH_LIBS)

test: $(TARGET)
	sh tests/smoke.sh

clean:
	rm -f $(TARGET)

CC ?= cc
CFLAGS ?= -std=c11 -Wall -Wextra -Werror -O2
READLINE_CFLAGS ?= $(shell pkg-config --cflags readline 2>/dev/null)
READLINE_LIBS ?= $(shell pkg-config --libs readline 2>/dev/null)
LDLIBS ?= -lm

ifneq ($(strip $(READLINE_LIBS)),)
READLINE_DEFINES := -DHAVE_READLINE
endif

TARGET := loco

.PHONY: all test clean

all: $(TARGET)

$(TARGET): loco.c
	$(CC) $(CFLAGS) $(READLINE_DEFINES) $(READLINE_CFLAGS) $< -o $@ $(READLINE_LIBS) $(LDLIBS)

test: $(TARGET)
	sh tests/smoke.sh

clean:
	rm -f $(TARGET)

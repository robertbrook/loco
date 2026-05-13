CC ?= cc
CFLAGS ?= -std=c11 -Wall -Wextra -Werror -O2
LDLIBS ?= -lm

TARGET := loco

.PHONY: all test clean

all: $(TARGET)

$(TARGET): loco.c
	$(CC) $(CFLAGS) $< -o $@ $(LDLIBS)

test: $(TARGET)
	sh tests/smoke.sh

clean:
	rm -f $(TARGET)

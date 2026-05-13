CC ?= cc
CFLAGS ?= -std=c11 -Wall -Wextra -Werror -O2

TARGET := loco

.PHONY: all test clean

all: $(TARGET)

$(TARGET): loco.c
	$(CC) $(CFLAGS) $< -o $@

test: $(TARGET)
	sh tests/smoke.sh

clean:
	rm -f $(TARGET)

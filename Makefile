CC ?= cc
CFLAGS ?= -std=c11 -Wall -Wextra -Werror -O2

TARGET := loco

.PHONY: all test clean

all: $(TARGET)

$(TARGET): /home/runner/work/loco/loco/loco.c
	$(CC) $(CFLAGS) $< -o $@

test: $(TARGET)
	sh /home/runner/work/loco/loco/tests/smoke.sh

clean:
	rm -f $(TARGET)

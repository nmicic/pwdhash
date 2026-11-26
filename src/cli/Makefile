CC ?= cc
CFLAGS ?= -O2 -std=c11 -Wall -Wextra -Wpedantic -fstack-protector-strong

.PHONY: all test clean
all: pwdhash
pwdhash: pwdhash.c
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) pwdhash.c -o $@
test: pwdhash
	./pwdhash --self-test
clean:
	rm -f pwdhash

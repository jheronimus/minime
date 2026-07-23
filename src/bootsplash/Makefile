CC ?= gcc
CFLAGS ?= -std=gnu11 -O2
LDFLAGS ?=

PKG_CONFIG ?= pkg-config
SDL_CFLAGS := $(shell $(PKG_CONFIG) --cflags sdl2)
SDL_LIBS := $(shell $(PKG_CONFIG) --libs sdl2)

bootsplash: bootsplash.o common.o dmg.o font.o gba.o gbc.o
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(SDL_LIBS) -lm

%.o: %.c
	$(CC) $(CFLAGS) $(SDL_CFLAGS) -c -o $@ $<

clean:
	rm -f bootsplash *.o

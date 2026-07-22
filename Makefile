CA65    = ca65
LD65    = ld65
CFLAGS  = -t vic20
TARGET  = vic99

SRCS    = $(wildcard *.s)
OBJS    = $(SRCS:.s=.o)

all: $(TARGET).prg

$(TARGET).prg: $(OBJS)
	$(LD65) -t vic20 -o $@ $^

%.o: %.s
	$(CA65) $(CFLAGS) -o $@ $<

clean:
	rm -f $(OBJS) $(TARGET).prg

run: $(TARGET).prg
	xvic $(TARGET).prg

.PHONY: all clean run

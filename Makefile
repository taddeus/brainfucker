LD := gcc
CC := clang
CFLAGS := -O3
LDFLAGS := -nostartfiles
BFFLAGS := -o
BFILES := $(patsubst %.b,%,$(wildcard *.b))

.PHONY: check clean
.PRECIOUS: $(addsuffix .ll,$(BFILES)) $(addsuffix -opt.ll,$(BFILES)) \
	$(addsuffix -c.c,$(BFILES)) $(addsuffix -nayuki.c,$(BFILES))

bf: bf.ml
	ocamlfind ocamlopt -linkpkg -package llvm -package str -o $@ -g $<
	rm -f $@.cmi $@.cmx $@.o

%-nayuki: LDFLAGS=
%: %.o
	$(LD) -o $@ $< $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -o $@ -c $<

%-nayuki.c: %.b
	python bfc.py $< $@

%.o: %.ll
	llc -filetype obj -o $@ $<

%.ll: %.bc
	llvm-dis -o $@ $<

%-opt.ll: %.ll
	opt -O3 -S -o $@ $<

%.ll: %.b bf
	./bf $(BFFLAGS) < $< > $@

%-c.c: %.b bf
	./bf $(BFFLAGS) -c < $< > $@

%.dump: %
	objdump -d -M intel $< > $@

check: hello-opt
	./$<

clean:
	rm -f bf *.cmi *.cmx *.ll *.bc *.o *.c *-opt *-c *-nayuki $(BFILES) *.dump

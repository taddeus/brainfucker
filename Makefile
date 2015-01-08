LD := clang
LDFLAGS := -nostartfiles
BFILES := $(wildcard *.b)

.PHONY: clean
.PRECIOUS: $(patsubst %.b,%.ll %-opt.ll,$(BFILES))

bf: bf.ml
	ocamlopt -o $@ -g -I /usr/lib/ocaml/llvm-3.5 llvm.cmxa $^

%: %.o
	$(LD) -o $@ $< $(LDFLAGS)

%.o: %.ll
	llc-3.5 -filetype obj -o $@ $<

%.ll: %.bc
	llvm-dis-3.5 -o $@ $<

%-opt.ll: %.ll
	opt-3.5 -O3 -S -o $@ $<

%.ll: %.b bf
	./bf < $< > $@

clean:
	rm -f bf *.cmi *.cmx *.ll *.bc *.o $(patsubst %.b,%,$(BFILES))

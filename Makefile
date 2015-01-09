LD := gcc
LDFLAGS := -nostartfiles
BFILES := $(patsubst %.b,%,$(wildcard *.b))

.PHONY: check clean
.PRECIOUS: $(addsuffix .ll,$(BFILES)) $(addsuffix -opt.ll,$(BFILES))

bf: bf.ml
	ocamlopt -o $@ -g -I /usr/lib/ocaml/llvm-3.4 llvm.cmxa $<
	rm -f $@.cmi $@.cmx $@.o

%: %.o
	$(LD) -o $@ $< $(LDFLAGS)

%.o: %.ll
	llc -filetype obj -o $@ $<

%.ll: %.bc
	llvm-dis -o $@ $<

%-opt.ll: %.ll
	opt -O3 -S -o $@ $<

%.ll: %.b bf
	./bf < $< > $@

check: hello-opt
	./$<

clean:
	rm -f bf *.cmi *.cmx *.ll *.bc *.o $(BFILES) $(addsuffix -opt,$(BFILES))

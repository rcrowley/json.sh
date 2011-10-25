VERSION=0.0.0
BUILD=0

prefix=/usr/local
bindir=${prefix}/bin
libdir=${prefix}/lib
mandir=${prefix}/share/man

all:

clean:

install:
	install bin/json.sh $(DESTDIR)$(bindir)/
	install lib/json.sh $(DESTDIR)$(libdir)/

uninstall:
	rm -f $(DESTDIR)$(bindir)/json.sh
	rm -f $(DESTDIR)$(libdir)/json.sh

test:
	sh test.sh

gh-pages:
	shocco lib/json.sh >json.sh.html+
	git checkout -q gh-pages
	mv json.sh.html+ json.sh.html
	git add json.sh.html
	git commit -m "Rebuilt docs."
	git push origin gh-pages
	git checkout -q master

.PHONY: all clean install uninstall test gh-pages

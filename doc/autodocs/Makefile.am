#
# Makefile.am for YCP module .../doc/autodocs
#

htmldir = @docdir@/autodocs

html_DATA = index.html $(wildcard *.html)
CLEANFILES = $(html_DATA)

index.html: $(srcdir)/../../src/inst/*.ycp
	@ybindir@/ycpdoc -d. $(srcdir)/../../src/inst/*.ycp

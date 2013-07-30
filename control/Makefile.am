#
# Makefile.am for wagon/src/config
#

controldir = $(yast2dir)/control

control_DATA = $(wildcard *.xml)

desktop_DATA = $(wildcard *.desktop)

EXTRA_DIST = $(desktop_DATA) $(control_DATA)

check-local:
	xmllint --relaxng $(controldir)/control.rng --noout $(control_DATA)

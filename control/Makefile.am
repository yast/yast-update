#
# Makefile.am for control
#

dist_control_DATA = $(wildcard *.xml)

check-local:
	xmllint --relaxng $(controldir)/control.rng --noout $(dist_control_DATA)

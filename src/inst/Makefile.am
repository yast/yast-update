#
# Makefile.am for update/src/inst
#

SUBDIRS = scripts

module_DATA =				\
	Update.ycp			\
	RootPart.ycp

client_DATA =				\
	inst_rootpart.ycp		\
	inst_update.ycp			\
	inst_backup.ycp			\
	inst_rpmupdate.ycp		\
	proposal_rootpart.ycp		\
	proposal_update.ycp		\
	proposal_packages.ycp		\
	proposal_backup.ycp

EXTRA_DIST = $(module_DATA) $(client_DATA)

include $(top_srcdir)/Makefile.am.common

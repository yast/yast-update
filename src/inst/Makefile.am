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
	rootpart_proposal.ycp		\
	update_proposal.ycp		\
	packages_proposal.ycp		\
	backup_proposal.ycp

EXTRA_DIST = $(module_DATA) $(client_DATA)

include $(top_srcdir)/Makefile.am.common

# Sources for update

module_DATA = \
  modules/Update.rb \
  modules/RootPart.rb \
  modules/SUSERelease.rb

client_DATA = \
  clients/inst_rootpart.rb \
  clients/inst_update_partition_auto.rb \
  clients/rootpart_proposal.rb \
  clients/update.rb \
  clients/inst_update_partition.rb \
  clients/packages_proposal.rb \
  clients/update_proposal.rb \
  clients/inst_backup.rb \
  clients/run_update.rb \
  clients/backup_proposal.rb

yncludedir = @yncludedir@/update
ynclude_DATA = \
  include/update/rootpart.rb

desktop_DATA = \
  desktop/org.opensuse.yast.Update.desktop

ylibclientdir = "${yast2dir}/lib/update/clients"
ylibclient_DATA = \
  lib/update/clients/inst_update_partition_auto.rb

scalabledir = @icondir@/hicolor/scalable/apps
scalable_DATA = \
  icons/hicolor/scalable/apps/yast-update.svg

EXTRA_DIST = $(module_DATA) $(client_DATA) $(ynclude_DATA) $(desktop_DATA) $(ylibclient_DATA) $(scalable_DATA)

include $(top_srcdir)/Makefile.am.common

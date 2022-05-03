# ------------------------------------------------------------------------------
# Copyright (c) 2006-2012 Novell, Inc. All Rights Reserved.
#
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail, you may find
# current contact information at www.novell.com.
# ------------------------------------------------------------------------------

# Module:  backup_proposal.ycp
#
# Author:  Arvin Schnell <arvin@suse.de>
#    Lukas Ocilka <locilka@suse.cz>
#
# Purpose:  Let user choose backup during update.
#
# $Id$
module Yast
  class BackupProposalClient < Client
    def main
      textdomain "update"

      Yast.import "HTML"
      Yast.import "Update"
      Yast.import "Installation"

      @func = Convert.to_string(WFM.Args(0))
      @param = Convert.to_map(WFM.Args(1))
      @ret = {}

      if @func == "MakeProposal"
        @force_reset = Ops.get_boolean(@param, "force_reset", false)
        @language_changed = Ops.get_boolean(@param, "language_changed", false)

        # call some function that makes a proposal here:
        #
        # DummyMod::MakeProposal( force_reset );

        # Fill return map

        if @force_reset
          Installation.update_backup_modified = true
          Installation.update_backup_sysconfig = true
          Installation.update_remove_old_backups = false
        end

        @tmp = []

        if Installation.update_backup_modified ||
            Installation.update_backup_sysconfig
          if Installation.update_backup_modified
            # TRANSLATORS: proposal item in the update summary
            @tmp = Builtins.add(@tmp, _("Create Backup of Modified Files"))
          end

          if Installation.update_backup_sysconfig
            @tmp = Builtins.add(
              @tmp,
              # TRANSLATORS: item in the update summary
              _("Create Backup of /etc/sysconfig Directory")
            )
          end
        else
          # TRANSLATORS: proposal item in the update summary
          @tmp = Builtins.add(@tmp, _("Do Not Create Backups"))
        end

        if Installation.update_remove_old_backups
          # TRANSLATORS: proposal item in the update summary
          @tmp = Builtins.add(@tmp, _("Remove Backups from Previous Updates"))
        end

        @ret = { "preformatted_proposal" => HTML.List(@tmp) }
      elsif @func == "AskUser"
        @has_next = Ops.get_boolean(@param, "has_next", false)

        # call some function that displays a user dialog
        # or a sequence of dialogs here:
        #
        # sequence = DummyMod::AskUser( has_next );

        @result = Convert.to_symbol(
          WFM.CallFunction("inst_backup", [true, @has_next])
        )

        # Fill return map

        @ret = { "workflow_sequence" => @result }
      elsif @func == "Description"
        # Fill return map.
        #
        # Static values do just nicely here, no need to call a function.

        @ret = {
          # TRANSLATORS: proposal heading
          "rich_text_title" => _("Backup"),
          # TRANSLATORS: a menu entry
          "menu_title"      => _("&Backup"),
          "id"              => "backup_stuff"
        }
      end

      deep_copy(@ret)
    end
  end
end

Yast::BackupProposalClient.new.main

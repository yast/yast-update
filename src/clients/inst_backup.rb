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

# Module:   inst_backup.ycp
#
# Authors:  Stefan Schubert <schubi@suse.de>
#    Arvin Schnell <arvin@suse.de>
#    Lukas Ocilka <locilka@suse.cz>
#
# Purpose:  Ask the user for backups during the update.
#
# $Id$
module Yast
  class InstBackupClient < Client
    def main
      Yast.import "UI"
      textdomain "update"

      Yast.import "Mode"
      Yast.import "Update"
      Yast.import "SpaceCalculation"
      Yast.import "Wizard"
      Yast.import "Popup"
      Yast.import "Installation"

      # Get information about available partitions
      @partition = Convert.convert(
        SpaceCalculation.GetPartitionInfo,
        from: "list",
        to:   "list <map>"
      )
      Builtins.y2milestone("evaluate partitions: %1", @partition)

      # TRANSLATORS: screen title for software selection
      @title = _("Backup System Before Update")

      # Build and show dialog

      Wizard.OpenOKDialog

      @contents = HVSquash(
        VBox(
          Left(
            CheckBox(
              Id(:modified),
              Opt(:notify),
              # TRANSLATORS: checkbox label if user wants to backup modified files
              _("Create &Backup of Modified Files")
            )
          ),
          Left(
            CheckBox(
              Id(:sysconfig),
              Opt(:notify),
              # TRANSLATORS: checkbox label if user wants to backup /etc/sysconfig
              _("Create a &Complete Backup of /etc/sysconfig")
            )
          ),
          VSpacing(1),
          Left(
            CheckBox(
              Id(:remove),
              Opt(:notify),
              # TRANSLATORS: checkbox label if user wants remove old backup stuff
              _("Remove &Old Backups from the Backup Directory")
            )
          )
        )
      )

      # TRANSLATORS: help text for backup dialog during update 1/7
      @help_text = _(
        "<p>To avoid any loss of information during update,\n" \
          "create a <b>backup</b> prior to updating.</p>\n"
      )

      # TRANSLATORS: help text for backup dialog during update 2/7
      @help_text = Ops.add(
        @help_text,
        _(
          "<p><b>Warning:</b> This will not be a complete\n" \
            "backup. Only modified files will be saved.</p>\n"
        )
      )

      # TRANSLATORS: help text for backup dialog during update 3/7
      @help_text = Ops.add(
        @help_text,
        _("<p>Select the desired options.</p>\n")
      )

      # TRANSLATORS: help text for backup dialog during update 4/7
      @help_text = Ops.add(
        @help_text,
        _(
          "<p><b>Create a Backup of Modified Files:</b>\n" \
            "Stores only those modified files that will be replaced during update.</p>\n"
        )
      )

      # TRANSLATORS: help text for backup dialog during update 5/7
      @help_text = Ops.add(
        @help_text,
        _(
          "<p><b>Create a Complete Backup of\n" \
            "/etc/sysconfig:</b> This covers all configuration files that are part of the\n" \
            "sysconfig mechanism, even those that will not be replaced.</p>\n"
        )
      )

      # TRANSLATORS: help text for backup dialog during update 6/7
      @help_text = Ops.add(
        @help_text,
        _(
          "<p><b>Remove Old Backups from the Backup\n" \
            "Directory:</b> If your current system already is the result of an earlier\n" \
            "update, there may be old configuration file backups. Select this option to\n" \
            "remove them.</p>\n"
        )
      )

      # TRANSLATORS: help text for backup dialog during update 7/7
      @help_text = Ops.add(
        @help_text,
        Builtins.sformat(
          _("<p>All backups are placed in %1.</p>"),
          Installation.update_backup_path
        )
      )

      Wizard.SetContents(
        @title,
        @contents,
        @help_text,
        Convert.to_boolean(WFM.Args(0)),
        Convert.to_boolean(WFM.Args(1))
      )

      UI.ChangeWidget(
        Id(:modified),
        :Value,
        Installation.update_backup_modified
      )
      UI.ChangeWidget(
        Id(:sysconfig),
        :Value,
        Installation.update_backup_sysconfig
      )
      UI.ChangeWidget(
        Id(:remove),
        :Value,
        Installation.update_remove_old_backups
      )

      @ret = nil

      loop do
        @ret = Wizard.UserInput

        break if @ret == :abort && Popup.ConfirmAbort(:painless)

        break if @ret == :cancel || @ret == :back

        # any backup wanted?
        @tmp = Convert.to_boolean(UI.QueryWidget(Id(:modified), :Value)) ||
          Convert.to_boolean(UI.QueryWidget(Id(:sysconfig), :Value))

        next unless @ret == :next || @ret == :ok
        next if @tmp && !check_backup_path(@partition)

        Installation.update_backup_modified = Convert.to_boolean(
          UI.QueryWidget(Id(:modified), :Value)
        )
        Installation.update_backup_sysconfig = Convert.to_boolean(
          UI.QueryWidget(Id(:sysconfig), :Value)
        )
        Installation.update_remove_old_backups = Convert.to_boolean(
          UI.QueryWidget(Id(:remove), :Value)
        )

        break
      end

      Wizard.CloseDialog

      deep_copy(@ret)
    end

    #
    # Check, if the backup fits to disk
    #

    def check_backup_path(part_info)
      part_info = deep_copy(part_info)
      backup_path = Installation.update_backup_path
      min_space = 50

      found = false
      free_space = 0

      if Ops.less_or_equal(Builtins.size(backup_path), 1) ||
          Builtins.substring(backup_path, 0, 1) != "/"
        # TRANSLATORS: error popup, user did not enter a valid directory specification
        Popup.Message(_("Invalid backup path."))
        return false
      end

      Builtins.foreach(part_info) do |part|
        part_name = Ops.get_string(part, "name", "")
        if part_name == "/" && !found
          free_space = Ops.get_integer(part, "free", 0)
          Builtins.y2milestone("Partition :%1", part_name)
          Builtins.y2milestone("free:%1", free_space)
        end
        if Ops.greater_or_equal(Builtins.size(backup_path), 2) &&
            part_name != "/"
          compare_string = Builtins.substring(
            backup_path,
            0,
            Builtins.size(part_name)
          )
          if compare_string == part_name && !found
            free_space = Ops.get_integer(part, "free", 0)
            Builtins.y2milestone("Partition :%1", part_name)
            Builtins.y2milestone("free:%1", free_space)
            found = true
          else
            Builtins.y2milestone(
              "Partition :%1<->%2",
              part_name,
              compare_string
            )
          end
        end
      end

      return true if Ops.greater_or_equal(free_space, min_space) || Mode.test

      # there is not enough space for the backup during update
      # inform the user about this (MB==megabytes)
      message = Builtins.sformat(
        # TRANSLATORS: popup message
        _("Minimum disk space of %1 MB required."),
        min_space
      )
      Popup.Message(message)
      false
    end
  end
end

Yast::InstBackupClient.new.main

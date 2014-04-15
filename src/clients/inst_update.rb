# encoding: utf-8

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

# Module: 		inst_update.ycp
#
# Authors:		Stefan Schubert <schubi@suse.de>
#			Arvin Schnell <arvin@suse.de>
#
# Purpose:
# Displays software selection screen of previous installed software-groups.
# Show checkboxes for software categories. Let the user select his software.
# if he want to UPGRADE his system.
#
# $Id$
module Yast
  class InstUpdateClient < Client
    def main
      Yast.import "UI"
      Yast.import "Pkg"
      textdomain "update"

      Yast.import "Wizard"
      Yast.import "Popup"
      Yast.import "RootPart"
      Yast.import "Update"
      Yast.import "Packages"
      Yast.import "Installation"

      # screen title for update options
      @title = _("Update Options")

      # push button label
      @baseconfsbox = PushButton(Id(:details), _("Select Patterns"))

      # Checking: already selected addons or single selection?

      @wrn_msg = ""

      if Pkg.RestoreState(true) # check if state changed
        # Display warning message
        @wrn_msg = _(
          "You have already chosen software from \"Detailed selection\".\nYou will lose that selection if you change the basic selection."
        )
      end

      # Build and show dialog

      @from_version = Ops.get_locale(
        Installation.installedVersion,
        "show",
        _("Unknown")
      )
      @to_version = Ops.get_locale(
        Installation.updateVersion,
        "show",
        _("Unknown")
      )

      @update_label = ""
      if @from_version == @to_version
        # label showing to which version we are updating
        @update_label = Builtins.sformat(_("Update to %1"), @to_version)
      else
        # label showing from which version to which version we are updating
        @update_label = Builtins.sformat(
          _("Update from %1 to %2"),
          @from_version,
          @to_version
        )
      end

      @contents = HVSquash(
        VBox(
          Left(Label(@update_label)),
          VSpacing(1),
          # frame title for update selection
          Frame(
            _("Update Mode"),
            VBox(
              VSpacing(1),
              RadioButtonGroup(
                Id(:bgoup),
                Opt(:notify),
                VBox(
                  Left(
                    RadioButton(
                      Id(:upgrade),
                      Opt(:notify),
                      # radio button label for update including new packages
                      _(
                        "&Update with Installation of New Software and Features\nBased on the Selection:\n"
                      ),
                      false
                    )
                  ),
                  VSpacing(0.5),
                  HBox(HSpacing(4), @baseconfsbox),
                  VSpacing(1.5),
                  Left(
                    RadioButton(
                      Id(:notupgrade),
                      Opt(:notify),
                      # radio button label for update of already installed packages only
                      _("Only U&pdate Installed Packages"),
                      true
                    )
                  ),
                  VSpacing(1.0)
                )
              )
            )
          ),
          #	      `VSpacing (1),
          #	      `Left(`CheckBox(`id(`delete),
          #			      // check box label
          #			      // translator: add a & shortcut
          #			      _("&Delete Unmaintained Packages"), true)),
          VSpacing(1),
          Label(Id(:wrn_label), @wrn_msg)
        )
      )


      # help text for dialog "update options" 1/4
      @helptext = _(
        "<p>The update option offers two different modes. In\neither case, we recommend to make a backup of your personal data.</p>\n"
      )

      # help text for dialog "update options" 2/4, %1 is a product name
      @helptext = Ops.add(
        @helptext,
        Builtins.sformat(
          _(
            "<p><b>With New Software:</b> This default setting\n" +
              "updates the existing software and installs all new features and benefits of\n" +
              "the new <tt>%1</tt> version. The selection is based on the former predefined\n" +
              "software selection.</p>\n"
          ),
          Ops.get_string(Installation.updateVersion, "show", "")
        )
      )

      # help text for dialog "update options" 3/4
      @helptext = Ops.add(
        @helptext,
        _(
          "<p><b>Only Installed Packages:</b> This selection\n" +
            "only updates the packages already installed on your system. <i>Note:</i>\n" +
            "New software in the predefined software selection, such as new YaST modules, is\n" +
            "not available after the update. You might miss new features.</p>\n"
        )
      )

      # help text for dialog "update options" 4/4
      @helptext = Ops.add(
        @helptext,
        _(
          "<p>After the update, some software might not\n" +
            "function anymore. Activate <b>Delete Unmaintained Packages</b> to delete those\n" +
            "packages during the update.</p>\n"
        )
      )


      Wizard.OpenOKDialog

      Wizard.SetContents(
        @title,
        @contents,
        @helptext,
        Convert.to_boolean(WFM.Args(0)),
        Convert.to_boolean(WFM.Args(1))
      )
      Wizard.SetTitleIcon("yast-software")

      # preset update/upgrade radio buttons properly

      UI.ChangeWidget(Id(:upgrade), :Value, !Update.onlyUpdateInstalled)
      UI.ChangeWidget(Id(:notupgrade), :Value, Update.onlyUpdateInstalled)

      #    UI::ChangeWidget(`id(`delete), `Value, Update::deleteOldPackages);

      @ret = nil
      @details_pressed = false

      while true
        @ret = Wizard.UserInput

        break if @ret == :abort && Popup.ConfirmAbort(:painless)

        if @ret == :details
          @result = :again
          while @result == :again
            @result = Convert.to_symbol(
              WFM.CallFunction("inst_sw_select", [true, true])
            )
          end
          @details_pressed = true if @ret == :next
          next
        end

        if (@ret == :next || @ret == :ok) && Pkg.RestoreState(true)
          new_onlyUpdateInstalled = UI.QueryWidget(Id(:notupgrade), :Value)
          # Selection has changed
          if Update.onlyUpdateInstalled != new_onlyUpdateInstalled
            # BNC#873122
            #   The default is 'do not onlyUpdateInstalled'
            #   New status is 'do onlyUpdateInstalled'
            if !Update.default_onlyUpdateInstalled && new_onlyUpdateInstalled
              next unless Popup::AnyQuestion(
                Label.WarningMsg,
                # warning / question
                _(
                  "Changing the update method to 'Update packages only' might\n" +
                  "lead into non-bootable or non-working system if you do not\n" +
                  "adjust the list of packages yourself.\n\n" +
                  "Really continue?"
                ),
                Label.YesButton,
                Label.NoButton,
                :focus_no
              )
            elsif Packages.base_selection_modified
              # yes/no question
              next unless Popup.YesNo(_("Do you really want\nto reset your detailed selection?"))
            end
          end
        end

        break if @ret == :back || @ret == :next || @ret == :ok
      end

      if @ret == :next || @ret == :ok
        Update.did_init1 = false

        @b1 = Update.onlyUpdateInstalled
        Update.onlyUpdateInstalled = UI.QueryWidget(Id(:notupgrade), :Value)

        if @b1 != Update.onlyUpdateInstalled || @details_pressed
          Update.manual_interaction = true
        end
      end

      Wizard.CloseDialog

      deep_copy(@ret)
    end
  end
end

Yast::InstUpdateClient.new.main

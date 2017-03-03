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

# Module:	include/installation/rootpart.ycp
#
# Authors:	Stefan Schubert <schubi@suse.de>
#		Arvin Schnell <arvin@suse.de>
#              Jiri Srain <jsrain@suse.cz>
#
# Purpose:	Select root partition for update or booting.
#		RootPart::rootPartitions must be filled before
#		calling this module.
require "yast"

module Yast
  module UpdateRootpartInclude
    include Yast::Logger

    def initialize_update_rootpart(include_target)
      Yast.import "UI"
      Yast.import "Pkg"
      textdomain "update"

      Yast.import "Wizard"
      Yast.import "Popup"
      Yast.import "Label"
      Yast.import "RootPart"
      Yast.import "GetInstArgs"
      Yast.import "Report"
      Yast.import "Update"
      Yast.import "Installation"
# storage-ng
=begin
      Yast.import "FileSystems"
=end
      Yast.import "Mode"
      Yast.import "Product"
    end

    # Returns boolean whether partition can be
    # a Linux 'root' file system
    def CanBeLinuxRootFS(partition_fs)
      if partition_fs.nil?
        Builtins.y2error("partition_fs not defined!")
        return false
      end

      # possible_root_fs contains list of supported FSs
      # storage-ng
      # FIXME: this kind of checks should be responsibility of the upcoming
      # Y2Storage::FilesystemType (to be added as part of the
      # "yast-storage-ng as a libstorage wrapper" change)
      possible_root_fs = [:ext2, :ext3, :ext4, :btrfs, :reiser, :xfs]
      possible_root_fs.include?(partition_fs)
    end

    # flavor is either `update or `boot
    def make_partition_list(withall, flavor)
      part_list = []
      Builtins.foreach(RootPart.rootPartitions) do |partition, i|
        # see https://bugzilla.novell.com/attachment.cgi?id=96783&action=view

        # see bugzilla #288201
        # architecture needs to be valid when updating, not booting
        arch_is_valid = flavor == :boot ?
          true :
          Ops.get_boolean(i, :arch_valid, false)
        if withall || Ops.get_boolean(i, :valid, false) && arch_is_valid
          # `ext2, `jfs, ...
          part_fs = Ops.get_symbol(i, :fs)
          part_fs_name = Builtins.tostring(part_fs)
          if part_fs_name != nil &&
              Builtins.regexpmatch(part_fs_name, "^`(.*)$")
            part_fs_name = Builtins.regexpsub(part_fs_name, "^`(.*)$", "\\1")
          end

          system = Ops.get_string(i, :name, "error")
          # unknown system
          if system == "unknown"
            if part_fs != nil
              if CanBeLinuxRootFS(part_fs)
                # Table item (unknown system)
                system = _("Unknown Linux")
              else
                # Table item (unknown system)
                system = _("Unknown or Non-Linux")
              end
            else
              # Table item (unknown system [neither openSUSE 11.1 nor SLES 14 nor ...])
              system = _("Unknown") if system == "unknown"
            end
          end

          arch = Ops.get_string(i, :arch, "error")
          # Table item (unknown architecture)
          arch = _("Unknown") if arch == "unknown"

          # fist, use the name of file system (with short name for Linux)
          # then the file system short name
          # then "Unknown"
          fs = ""

          # is a linux fs, can be a root fs, has a fs name
          if part_fs != nil && Ops.get(i, :fstype) != nil &&
              CanBeLinuxRootFS(part_fs) &&
              part_fs_name != nil
            fs = Builtins.sformat(
              _("%1 (%2)"),
              Ops.get_string(i, :fstype, ""),
              part_fs_name
            )
          else
            fs = Ops.get_string(i, :fstype, Ops.get_string(i, :fs, ""))
          end
          # Table item (unknown file system)
          fs = _("Unknown") if fs == ""

          label = Ops.get_string(i, :label, "")

          part_list = Builtins.add(
            part_list,
            Item(Id(partition), system, partition, arch, fs, label)
          )
        end
      end
      deep_copy(part_list)
    end

    # Returns whether wanted and selected architectures match
    # bnc #372309
    def DoArchitecturesMatch(arch_1, arch_2)
      ppc_archs = ["ppc", "ppc64"]

      # exact match
      if arch_1 == arch_2
        return true 
        # ppc exception
      elsif Builtins.contains(ppc_archs, arch_1) &&
          Builtins.contains(ppc_archs, arch_2)
        return true
      end

      # else
      false
    end

    def UmountMountedPartition
      Update.Detach
      RootPart.UnmountPartitions(false)

      nil
    end

    # This dialog comes in several different flavors:
    # `update_dialog - used to show partitions available for upgrade,
    # `update_popup - obsolete, used to be used as a pop-up in proposal dialog (MakeProposal),
    # `update_dialog_proposal - obsolete, used to be used as a pop-up in proposal dialog (AskUser),
    # `boot_popup - obsolete, used to be used as a dilaog offering to boot to a selected partition,
    #
    # @param [Symbol] flavor
    # @return [Symbol] `cancel, `back, `next, `abort
    def RootPartitionDialog(flavor)
      # FIXME: Most of the code in this function is obsolete

      partition_list = make_partition_list(
        RootPart.showAllPartitions,
        flavor == :boot_popup ? :boot : :update
      )

      title = ""
      label = ""
      help_text = ""

      if flavor == :boot_popup
        # label for selection of root partition (for boot)
        label = _("Partition or System to Boot:")

        # help text for root partition dialog (for boot)
        help_text = _(
          "<p>\n" +
            "Select the partition or system to boot.\n" +
            "</p>\n"
        )
      else
        # label for selection of root partition (for update)
        label = _("Partition or System to Update:")

        # help text for root partition dialog (for update)
        help_text = _(
          "<p>\n" +
            "Select the partition or system to update.\n" +
            "</p>\n"
        )

        if flavor == :update_dialog || flavor == :update_dialog_proposal
          # headline for dialog "Select for update"
          title = _("Select for Update")
        end
      end

      # help text for root partition dialog (general part)
      help_text = Ops.add(
        help_text,
        _(
          "<p>\n" +
            "<b>Show All Partitions</b> expands the list to a\n" +
            "general overview of your system's partitions.\n" +
            "</p>\n"
        )
      )

      contents = HBox(
        VBox(
          VSpacing(1),
          Left(Label(label)),
          MinSize(
            70,
            14,
            Table(
              Id(:partition),
              Opt(:hstretch),
              Header(
                # table header
                _("System"),
                # table header item
                _("Partition"),
                # table header item
                _("Architecture"),
                # table header item
                _("File System"),
                # table header item
                _("Label")
              ),
              partition_list
            )
          ),
          Left(
            CheckBox(
              Id(:showall),
              Opt(:notify),
              # check box
              _("&Show All Partitions"),
              false
            )
          ),
          VSpacing(1)
        )
      )

      # bnc #429080
      # finishing the target before selecting a new system to load
      Pkg.TargetFinish if flavor == :update_dialog

      if flavor == :update_dialog
        Wizard.SetContents(title, contents, help_text, true, true)
        Wizard.EnableAbortButton if Mode.autoupgrade
      elsif flavor == :update_dialog_proposal
        Wizard.CreateDialog
        Wizard.SetContentsButtons(
          title,
          contents,
          help_text,
          Label.BackButton,
          Label.OKButton
        )
      else
        buttons = PushButton(Id(:next), Opt(:default), Label.OKButton)

        if flavor == :boot_popup
          buttons = HBox(
            HStretch(),
            # pushbutton to (rightaway) boot the system selected above
            HWeight(1, PushButton(Id(:next), Opt(:default), _("&Boot"))),
            HSpacing(1),
            HWeight(1, PushButton(Id(:cancel), Label.CancelButton)),
            HStretch()
          )
        end

        full = MinHeight(
          16,
          HBox(
            HSquash(MinWidth(26, RichText(Opt(:vstretch), help_text))),
            HSpacing(2),
            VBox(MinHeight(15, contents), buttons),
            HSpacing(2)
          )
        )

        UI.OpenDialog(full)
      end


      if Ops.greater_than(Builtins.size(RootPart.selectedRootPartition), 0)
        UI.ChangeWidget(
          Id(:partition),
          :CurrentItem,
          RootPart.selectedRootPartition
        )
      end

      UI.ChangeWidget(Id(:showall), :Value, RootPart.showAllPartitions)


      ret = nil

      while true
        if flavor == :update_dialog || flavor == :update_dialog_proposal
          ret = Wizard.UserInput
        else
          ret = UI.UserInput
        end

        ret = :abort if ret == :cancel
        break if ret == :abort && Popup.ConfirmAbort(:painless)

        if ret == :showall
          tmp = Convert.to_string(UI.QueryWidget(Id(:partition), :CurrentItem))
          partition_list = make_partition_list(
            Convert.to_boolean(UI.QueryWidget(Id(:showall), :Value)),
            flavor == :boot_popup ? :boot : :update
          )
          UI.ChangeWidget(Id(:partition), :Items, partition_list)
          UI.ChangeWidget(Id(:partition), :CurrentItem, tmp) if tmp != nil
          next
        end
        if (flavor == :update_dialog || flavor == :update_popup ||
            flavor == :update_dialog_proposal) &&
            ret == :next
          selected = Convert.to_string(
            UI.QueryWidget(Id(:partition), :CurrentItem)
          )
          freshman = Ops.get(RootPart.rootPartitions, selected, {})
          cont = true
          Builtins.y2milestone(
            "Selected root partition: %1 %2",
            selected,
            freshman
          )
          if Ops.get_string(freshman, :name, "unknown") == "unknown"
            cont = false
            Popup.Error(
              # error popup
              _(
                "No installed system that can be upgraded with this product was found\non the selected partition."
              )
            )
          elsif !DoArchitecturesMatch(
              Ops.get_string(freshman, :arch, ""),
              RootPart.GetDistroArch
            )
            cont = Popup.ContinueCancel(
              # continue-cancel popup
              _(
                "The architecture of the system installed in the selected partition\nis different from the one of this product.\n"
              )
            )
          end
          ret = nil if !cont
        end
        if ret == :next
          RootPart.selectedRootPartition = Convert.to_string(
            UI.QueryWidget(Id(:partition), :CurrentItem)
          )
          RootPart.showAllPartitions = Convert.to_boolean(
            UI.QueryWidget(Id(:showall), :Value)
          )

          if flavor == :update_dialog
            RootPart.targetOk = RootPart.mount_target

            # Not mounted correctly
            if !RootPart.targetOk
              # error report
              Report.Error(_("Failed to mount target system"))
              UmountMountedPartition()
              next 

              # Correctly mounted but incomplete installation found
            elsif RootPart.IncompleteInstallationDetected(Installation.destdir)
              if Popup.AnyQuestion(
                  Label.WarningMsg,
                  # pop-up question
                  _(
                    "A possibly incomplete installation has been detected on the selected partition.\nAre sure you want to use it anyway?"
                  ),
                  # button label
                  _("&Yes, Use It"),
                  Label.CancelButton,
                  :focus_no
                )
                Builtins.y2milestone(
                  "User wants to update possibly incomplete system"
                )
              else
                Builtins.y2milestone(
                  "User decided not to update incomplete system"
                )
                UmountMountedPartition()
                next
              end
            end
          end
          break
        end
        break if ret == :cancel || ret == :back || ret == :next
      end

      if flavor != :update_dialog
        UI.CloseDialog
      elsif Mode.autoupgrade
        Wizard.DisableAbortButton
      end

      # New partition has been mounted
      if flavor == :update_dialog && ret == :next
        # override the current target distribution at the system and use
        # the target distribution from the base product to make the new service
        # repositories compatible with the base product at upgrade (bnc#881320)
        if Pkg.TargetInitializeOptions(Installation.destdir,
            "target_distro" => target_distribution) != true
          # Target load failed, #466803
          Builtins.y2error("Pkg::TargetInitialize failed")
          if Popup.AnyQuestion(
              Label.ErrorMsg,
              _(
                "Initializing the system for upgrade has failed for unknown reason.\n" +
                  "It is highly recommended not to continue the upgrade process.\n" +
                  "\n" +
                  "Are you sure you want to continue?"
              ),
              _("&Yes, Continue"),
              Label.CancelButton,
              :focus_no
            )
            ret = :back
          else
            Builtins.y2warning(
              "User decided to continue despite the error above (Pkg::TargetInit() failed)"
            )
          end
        end

        # not aborted
        if ret != :back
          # Target load failed, #466803
          if Pkg.TargetLoad != true
            Builtins.y2error("Pkg::TargetLoad failed")
            if Popup.AnyQuestion(
                Label.ErrorMsg,
                _(
                  "Initializing the system for upgrade has failed for unknown reason.\n" +
                    "It is highly recommended not to continue the upgrade process.\n" +
                    "\n" +
                    "Are you sure you want to continue?"
                ),
                _("&Yes, Continue"),
                Label.CancelButton,
                :focus_no
              )
              ret = :back
            else
              Builtins.y2warning(
                "User decided to continue despite the error above (Pkg::TargetLoad() failed)"
              )
            end
          end
        end
      end

      Convert.to_symbol(ret)
    end

    def target_distribution
      base_products = Product.FindBaseProducts

      # empty target distribution disables service compatibility check in case
      # the base product cannot be found
      target_distro = base_products ? base_products.first["register_target"] : ""
      log.info "Base product target distribution: #{target_distro}"

      target_distro
    end

  end
end

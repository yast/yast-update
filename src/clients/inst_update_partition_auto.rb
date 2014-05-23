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

# Module:	inst_update_partition.ycp
#
# Authors:	Stefan Schubert <schubi@suse.de>
#		Arvin Schnell <arvin@suse.de>
#
# Purpose:	Select root partition for update or booting.
#		RootPart::rootPartitions must be filled before
#		calling this module.
#
# $Id:$
module Yast
  class InstUpdatePartitionAutoClient < Client
    def main
      Yast.import "Pkg"
      Yast.import "UI"
      textdomain "update"

      Yast.import "ProductControl"
      Yast.import "RootPart"

      Yast.include self, "update/rootpart.rb"

      if RootPart.Mounted
        Update.Detach
        RootPart.UnmountPartitions(false)
      end

      RootPart.Detect
      # if there is only one suitable partition which can be mounted, use it without asking
      @target_system = ""


      @partitions = Builtins.filter(RootPart.rootPartitions) do |name, p|
        @target_system = name if Ops.get_boolean(p, :valid, false)
        Ops.get_boolean(p, :valid, false)
      end

      # allow to specicfy the target on cmdline (e.g. if there are multiple systems)
      # ptoptions=TargetRoot target_root=<device> (bnc#875031)
      install_inf_target_system = Linuxrc.InstallInf("TargetRoot")
      if install_inf_target_system
        @target_system = install_inf_target_system
        @partitions = { @target_system => { :valid => true } }
        Builtins.y2milestone("Selecting system %1 specified in install.inf", @target_system);
      end

      if Builtins.size(@partitions) == 1
        Builtins.y2milestone(
          "Auto-mounting system located at %1",
          @target_system
        )
        RootPart.selectedRootPartition = @target_system
        RootPart.targetOk = RootPart.mount_target

        # Not mounted correctly
        if !RootPart.targetOk
          # error report
          Report.Error(_("Failed to mount target system"))
          UmountMountedPartition() 
          # Correctly mounted but incomplete installation found
        elsif RootPart.IncompleteInstallationDetected(Installation.destdir)
          Report.Error(
            _("A possibly incomplete installation has been detected.")
          )
          UmountMountedPartition()
        elsif !(Pkg.TargetInitialize(Installation.destdir) && Pkg.TargetLoad)
          Report.Error("Initializing the target system failed")
          UmountMountedPartition()
          Pkg.TargetFinish
        else
          return :next
        end
      end
      @ret = RootPartitionDialog(:update_dialog)

      @ret
    end
  end
end

Yast::InstUpdatePartitionAutoClient.new.main

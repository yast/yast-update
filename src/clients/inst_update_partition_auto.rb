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

require "yaml"

module Yast
  class InstUpdatePartitionAutoClient < Client
    include Logger

    DATA_PATH = "/var/lib/YaST2/update_partition_auto.yaml".freeze

    def main
      Yast.import "Pkg"
      Yast.import "UI"

      textdomain "update"

      Yast.import "ProductControl"
      Yast.import "RootPart"

      Yast.include self, "update/rootpart.rb"

      # In case of restarting after a installer update, we restore previous
      # data if exists (bsc#988287)
      load_data if Installation.restarting? && data_stored?

      if RootPart.Mounted
        log.debug("RootPart is mounted, detaching Update & unmounting partitions")
        Update.Detach
        RootPart.UnmountPartitions(false)
      end

      RootPart.Detect

      # if there is only one suitable partition which can be mounted, use it without asking
      @target_system = current_target_system

      if @target_system
        log.info("Auto-mounting system located at #{@target_system}")

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
        elsif !(Pkg.TargetInitializeOptions(Installation.destdir,
          "target_distro" => target_distribution) && Pkg.TargetLoad)

          Report.Error("Initializing the target system failed")
          UmountMountedPartition()
          Pkg.TargetFinish
        else
          store_data

          return :next
        end
      end

      @ret = RootPartitionDialog(:update_dialog)

      store_data if @ret == :next

      @ret
    end

  private

    # @return <Boolean> true if dumped file data exists.
    def data_stored?
      ::File.exist?(DATA_PATH)
    end

    # Save some important RootPart attributes into a yaml file.
    def store_data
      data = {
        "activated"  => RootPart.GetActivated,
        "selected"   => RootPart.selectedRootPartition,
        "previous"   => RootPart.previousRootPartition,
        "partitions" => RootPart.rootPartitions
      }

      File.write(DATA_PATH, data.to_yaml)
    end

    # Loads RootPart data from a dump yaml file and delete the file after that.
    # It also remember the current root selection as the target_system
    def load_data
      data = YAML.load(File.read(DATA_PATH))

      log.debug("Loading data from dump file: #{data}")
      RootPart.load_saved(data)

      root_target = RootPart.selectedRootPartition || ""

      @target_system = root_target unless root_target.empty?

      ::FileUtils.rm_rf(DATA_PATH)
    end

    # Obtains the target system from the install.inf file or use the current
    # partitions if there is only 1 valid.
    #
    # @return [String] target root or nil
    def current_target_system
      return @target_system if Installation.restarting?

      # allow to specicfy the target on cmdline (e.g. if there are multiple systems)
      # ptoptions=TargetRoot target_root=<device> (bnc#875031)
      target_root = Linuxrc.InstallInf("TargetRoot")
      if target_root
        log.info("Selecting system #{target_root} specified in install.inf")

        return target_root
      end

      @partitions = RootPart.rootPartitions.select do |name, partition|
        target_root = name if partition[:valid]
        partition[:valid]
      end

      @partitions.size == 1 ? target_root : nil
    end
  end
end

Yast::InstUpdatePartitionAutoClient.new.main

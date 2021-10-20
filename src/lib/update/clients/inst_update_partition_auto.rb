# ------------------------------------------------------------------------------
# Copyright (c) 2016 SUSE LLC, All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# ------------------------------------------------------------------------------
#
# Authors:  Stefan Schubert <schubi@suse.de>
#    Arvin Schnell <arvin@suse.de>
#
# Purpose:  Select root partition for update or booting.
#    RootPart::rootPartitions must be filled before
#    calling this module.
#
# $Id:$

require "yaml"
require "y2packager/medium_type"
require "y2packager/product_spec"

module Yast
  class InstUpdatePartitionAutoClient < Client
    include Logger

    DATA_PATH = "/var/lib/YaST2/update_partition_auto.yaml".freeze

    def initialize
      Yast.import "Pkg"
      Yast.import "UI"

      textdomain "update"

      Yast.import "ProductControl"
      Yast.import "RootPart"

      Yast.include self, "update/rootpart.rb"
    end

    def main
      if RootPart.Mounted
        log.debug("RootPart is mounted, detaching Update & unmounting partitions")
        Update.Detach
        RootPart.UnmountPartitions(false)
      end

      RootPart.Detect

      # if there is only one suitable partition which can be mounted, use it without asking
      @target_system = target_system_candidate if @target_system.to_s.empty?

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
          "target_distro" => target_distro) && Pkg.TargetLoad)

          Report.Error("Initializing the target system failed")
          UmountMountedPartition()
          Pkg.TargetFinish
        else
          return :next
        end
      end

      @ret = RootPartitionDialog(:update_dialog)
    end

  private

    # Obtains the target system from the install.inf file or use the current
    # partitions if there is only 1 valid.
    #
    # @return [String, nil] target root or nil
    def target_system_candidate
      # allow to specicfy the target on cmdline (e.g. if there are multiple systems)
      # ptoptions=TargetRoot target_root=<device> (bnc#875031)
      target_root = Linuxrc.InstallInf("TargetRoot")
      if target_root
        log.info("Selecting system #{target_root} specified in install.inf")

        return target_root
      end

      partitions = RootPart.rootPartitions.select do |name, partition|
        target_root = name if partition[:valid]
        partition[:valid]
      end

      (partitions.size == 1) ? target_root : nil
    end

    # special version that respect online specific target distro
    def target_distro
      product = Y2Packager::ProductSpec.base_products.find { |p| p.respond_to?(:register_target) }
      if product
        product.register_target || ""
      else
        target_distribution
      end
    end
  end
end

# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2006-2012 Novell, Inc. All Rights Reserved.
# Copyright (c) 2018 SUSE LLC, All Rights Reserved.
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

module Yast
  class InstUpdatePartitionClient < Client
    include Yast::Logger

    def main
      Yast.import "UI"
      Yast.import "Pkg"
      textdomain "update"

      Yast.import "ProductControl"
      Yast.import "RootPart"
      Yast.import "GetInstArgs"

      Yast.include self, "update/rootpart.rb"

      if Yast::GetInstArgs.going_back
        # if going back restore the initial installation repositories
        restore_installation_repos
      else
        # if going forward save the installation repos for later
        save_installation_repos
      end

      if RootPart.Mounted
        Update.restore_backup
        Update.Detach
        RootPart.UnmountPartitions(false)
      end

      RootPart.Detect

      @ret = RootPartitionDialog(:update_dialog)

      if @ret == :next
        @ret = ProductControl.RunFrom(
          Ops.add(ProductControl.CurrentStep, 1),
          false
        )
        @ret = :finish if @ret == :next
      end

      @ret
    end

  private

    # restore the repository setup from the saved config
    def restore_installation_repos
      log.info("Restoring the initial repository setup")

      # drop the currently loaded repositories
      Yast::Pkg.SourceFinishAll
      # move the target from "/mnt" to "/"
      Yast::Pkg.TargetFinish
      Yast::Pkg.TargetInitialize("/")
      # load the previous repositories from the inst-sys ("/")
      Yast::Pkg.SourceRestore
      Yast::Pkg.SourceLoad

      restored = Yast::Pkg.SourceGetCurrent(false).map do |r|
        Yast::Pkg.SourceGeneralData(r)["url"]
      end
      log.info("Restored repositories: #{restored}")
    end

    # save the current repository setup
    def save_installation_repos
      log.info("Storing a backup of the current repository setup")
      Yast::Pkg.SourceSaveAll
    end
  end
end

Yast::InstUpdatePartitionClient.new.main

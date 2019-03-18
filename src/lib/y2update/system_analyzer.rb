# encoding: utf-8

# Copyright (c) [2019] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require "yast"
require "y2storage/existing_filesystem"

Yast.import "Linuxrc"
Yast.import "ModuleLoading"
Yast.import "UI"
Yast.import "Installation"

module Y2Update
  class SystemAnalyzer
    include Logger

    def initialize(devicegraph)
      textdomain "update"

      @devicegraph = devicegraph
    end

    # def filesystems
    #   @filesystems ||= find_all_filesystems
    # end

    # def root_filesystems
    #   @root_filesystems ||= find_root_filesystems
    # end

    # def data_for(filesystem)
    #   read_filesystems_data

    #   @filesystems_data[filesystem.sid]
    # end

    def filesystems_data
      @filesystems_data ||= read_filesystems_data
    end

  private

    STORAGE_KERNEL_MODULES = {
      "xfs"           => "XFS",
      "ext3"          => "Ext3",
      "ext4"          => "Ext4",
      "btrfs"         => "BtrFS",
      "raid0"         => "Raid 0",
      "raid1"         => "Raid 1",
      "raid5"         => "Raid 5",
      "raid6"         => "Raid 6",
      "raid10"        => "Raid 10",
      "dm-multipath"  => "Multipath",
      "dm-mod"        => "DM",
      "dm-snapshot"   => "DM Snapshot"
    }.freeze

    NON_MODULAR_FILESYSTEMS = ["devtmpfs", "proc", "sysfs"].freeze

    # all formatted partitions and lvs on all devices
    # def find_all_filesystems
    #   devicegraph.blk_filesystems.reject { |fs| fs.type.is?(:swap) }
    # end

    def filesystems
      @filesystems ||= devicegraph.blk_filesystems.reject { |fs| fs.type.is?(:swap) }
    end

    # def find_root_filesystems
    #   load_modules

    #   read_filesystems_data
    # end

    def read_filesystems_data
      load_modules

      filesystems_data = []

      init_progress_bar

      filesystems.each do |filesystem|
        update_progress_bar(filesystems.size, filesystems.index(filesystem))

        filesystems_data << read_filesystem_data(filesystem)
      end

      complete_progress_bar

      filesystems_data
    end

    def load_modules
      STORAGE_KERNEL_MODULES.each do |mod, name|
        ModuleLoading.Load(mod.to_s, "", "Linux", name, Linuxrc.manual, true)
      end
    end

    def init_progress_bar
      return unless progress_bar?

      UI.ReplaceWidget(
        Id("search_progress"),
        ProgressBar(
          Id("search_pb"),
          _("Evaluating root partition. One moment please..."),
          100,
          0
        )
      )
    end

    # 100%
    def complete_progress_bar
      return unless progress_bar?

      UI.ChangeWidget(Id("search_pb"), :Value, 100)
    end

    def update_progress_bar(total, current)
      return unless progress_bar?

      percent = 100 * (current + 1 / total)
      UI.ChangeWidget(Id("search_pb"), :Value, percent)
    end

    def progress_bar?
      UI.WidgetExists(Id("search_progress"))
    end

    def read_filesystem_data(filesystem)
      filesytem_data = FilesystemData.new(filesystem)

      return filesystem_data unless root_filesystem_type?(filesystem)

      if filesystem.type.is?(:jfs) && !pass_jfs_check?(filesystem)
        filesystem_data.valid_root = false
        return filesystems_data
      end

      modprobe(filesystem)

      existing_fs = Y2Storage::ExistingFilesystem.new(filesystem, "/", Installation.destdir)

      return filesystems_data unless existing_fs.fstab

      first_fstab_entry = existing_fs.fstab.entries.first

      filesystem_data.valid_root = fstab_entry_matches?(first_fstab_entry, filesystem)

      # we dont care about the other checks in autoinstallation
      return filesystems_data if Mode.autoinst

      filesystem_data.valid_root = false unless supported_for_upgrade?(existing_fs.release_name)

      # TRANSLATORS: label for an unknown installed system
      filesystem_data.release_name = existing_fs.release_name || _("Unknown")

      filesystem_data.arch = existing_fs.arch

      instsys_arch = GetArchOfELF("/bin/bash")

      if existing_fs.arch == instsys_arch
        # bsc##288201
        filesystem_data.valid_arch = true
      elsif ["ppc", "ppc64"].include?(existing_fs.arch) && ["ppc", "ppc64"].include?(instsys_arch)
        # bsc#249791
        filesystem_data.valid_arch = true
      else
        filesystem_data.valid_arch = false
        filesystem_data.valid = false
      end

      filesystem_data.valid_root = false if existing_fs.incomplete_installation?
    end

    def root_filesystem_type?(filesystem)
      filesystem.type.root_ok? || filesystem.type.legacy_root?
    end

    def pass_jfs_check?(filesystem)

    end

    def modprobe(filesystem)
      mount_type = filesystem.type.to_s

      # mustn't be empty and must be modular
      return if mount_type == "" || NON_MODULAR_FILESYSTEMS.include?(mount_type)

      log.debug("Calling modprobe #{mount_type}")
      SCR.Execute(path(".target.modprobe"), mount_type, "")
    end


  end
end
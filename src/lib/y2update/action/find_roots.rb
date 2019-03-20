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
require "yast/i18n"
require "y2update/filesystem_data"
require "y2update/jfs_checker"
require "y2update/dialog/mount_question"
require "y2update/widget/progress_bar_handler"

Yast.import "Linuxrc"
Yast.import "ModuleLoading"
Yast.import "Installation"

module Y2Update
  module Action
    class FindRoots
      include Yast::Logger
      include Yast::I18n

      attr_reader :filesystems_data

      def initialize(devicegraph)
        textdomain "update"

        @devicegraph = devicegraph
        @filesystems_data = []
      end

      def run
        load_modules

        progress_bar.show

        filesystems.each do |filesystem|
          progress_bar.update(filesystems.size, filesystems.index(filesystem))

          @filesystems_data << filesystem_data(filesystem)
        end

        progress_bar.complete

        true
      end

      def root_filesystems_data
        filesystems_data.select(&:valid_root?)
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

      def load_modules
        STORAGE_KERNEL_MODULES.each do |mod, name|
          ModuleLoading.Load(mod.to_s, "", "Linux", name, Linuxrc.manual, true)
        end
      end

      def progress_bar
        return @progress_bar if @progress_bar

        message = _("Evaluating root partition. One moment please...")
        @progress_bar = Y2Update::Widget::ProgressBarHandler.new(message)
      end

      def filesystems
        @filesystems ||= devicegraph.blk_filesystems.reject { |fs| fs.type.is?(:swap) }
      end

      def filesystem_data(filesystem)
        mount = mount_filesystem?(filesystem)

        FilesystemData.new(filesystem, mount: mount)
      end

      def mount_filesystem?(filesystem)
        return false unless root_filesystem_type?(filesystem)

        filesystem.type.is?(:jfs) ? mount_jfs_filesystem?(filesystem) : true
      end

      def root_filesystem_type?(filesystem)
        filesystem.type.root_ok? || filesystem.type.legacy_root?
      end

      def mount_jfs_filesystem?(filesystem)
        checker = JFSChecker.new(filesystem)

        return true if checker.valid?

        device_name = device_name(filesystem)
        error_message = checker.error_message(stdout: true)

        Dialog::MountQuestion.new(device_name, error_message).run
      end

      def device_name(filesystem)
        filesystem.blk_devices.first.name
      end
    end
  end
end
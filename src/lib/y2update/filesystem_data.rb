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
  class FilesystemData
    def initialize(filesystem, mount: true)
      @filesystem = filesystem
      @mount_allowed = mount

      default_data

      @processed = false
    end

    def valid_root?
      read_data unless processed?

      @valid_root
    end

    def valid_arch?
      read_data unless processed?

      @valid_arch
    end

    def arch
      read_data unless processed?

      @arch
    end

    def release_name
      read_data unless processed?

      @release_name
    end

  private

    attr_reader :filesystem

    attr_reader :mount_allowed

    attr_reader :processed

    alias_method :mount_allowed, :mount_allowed?

    alias_method :processed, :processed?

    def default_data
      @valid_root = false
      @valid_arch = false
      @arch = "unknown"
      @release_name = "unknown"
    end

    def existing_filesystem
      return @existing_filesystem unless @existing_filesystem.nil?

      modprobe(filesystem)

      @existing_filesystem = Y2Storage::ExistingFilesystem.new(filesystem)
    end

    def fstab?
      !existing_filesystem.fstab.nil?
    end

    def modprobe(filesystem)
      mount_type = filesystem.type.to_s

      # mustn't be empty and must be modular
      return if mount_type == "" || NON_MODULAR_FILESYSTEMS.include?(mount_type)

      log.debug("Calling modprobe #{mount_type}")
      SCR.Execute(path(".target.modprobe"), mount_type, "")
    end

    def use_default_data?
      !mount_allowed? || !fstab?
    end

    def read_data
      @processed = true

      return if use_default_data?

      @valid_root = check_valid_root
      @valid_arch = check_valid_arch
      @arch = read_arch
      @release_name = read_release_name
    end

    def check_valid_root

    end

    def check_valid_arch

    end

    def read_arch

    end

    def read_release_name

    end

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




  end
end
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
require "y2storage/existing_filesystem"
require "y2storage/elf_arch"

Yast.import "Mode"
Yast.import "ProductFeatures"

module Y2Update
  class FilesystemData
    include Yast::I18n
    include Yast::Logger

    attr_reader :arch

    attr_reader :release_name

    attr_reader :mount_allowed

    alias_method :mount_allowed, :mount_allowed?

    def initialize(filesystem, mount: true)
      @filesystem = filesystem
      @mount_allowed = mount

      read
    end

    def valid_root?
      @valid_root
    end

    def valid_arch?
      @valid_arch
    end

    def label
      filesystem.label
    end

    def type
      filesystem.type
    end

    # storage-ng
    # this is the closest equivalent we have in storage-ng
    def device_type
      if device.is?(:partition)
        device.id.to_human_string
      elsif device.is?(:lvm_lv)
        "LV"
      else
        nil
      end
    end

    def device
      filesystem.blk_devices.first
    end

  private

    attr_reader :filesystem

    def read
      default_data

      return if use_default_data?

      @valid_root = check_valid_root

      # we dont care about the other checks in autoinstallation
      return if Yast::Mode.autoinst

      @valid_arch = check_valid_arch
      @arch = read_arch
      @release_name = read_release_name
    end

    def default_data
      @valid_root = false
      @valid_arch = false
      @arch = "unknown"
      @release_name = "unknown"
    end

    def use_default_data?
      !mount_allowed? || !fstab?
    end

    def fstab?
      !fstab.nil?
    end

    def fstab
      existing_filesystem.fstab
    end

    def existing_filesystem
      return @existing_filesystem unless @existing_filesystem.nil?

      modprobe(filesystem)

      @existing_filesystem = Y2Storage::ExistingFilesystem.new(filesystem)
    end

    def modprobe(filesystem)
      mount_type = filesystem.type.to_s

      # mustn't be empty and must be modular
      return if mount_type == "" || NON_MODULAR_FILESYSTEMS.include?(mount_type)

      log.debug("Calling modprobe #{mount_type}")
      SCR.Execute(path(".target.modprobe"), mount_type, "")
    end

    def check_valid_root
      first_fstab_entry_match?

      # we dont care about the other checks in autoinstallation
      return if Yast::Mode.autoinst

      product_supported_for_upgrade? && !incomplete_installation?
    end

    def check_valid_arch
      instsys_arch = Y2Storage::ELFArch.new("/").value

      filesystem_arch = existing_filesystem.elf_arch

      equal_arch?(instsys_arch, filesystem_arch)
    end

    def read_arch
      existing_filesystem.elf_arch
    end

    def read_release_name
      # TRANSLATORS: label for an unknown installed system
      existing_filesystem.release_name || _("Unknown")
    end

    def product_supported_for_upgrade?
      product = existing_filesystem.release_name

      return false if product.nil? || product.empty?

      supported_products = Yast::ProductFeatures.GetFeature(
        "software",
        "products_supported_for_upgrade"
      )

      supported_products.any? { |p| Regexp.new(p).match?(product) }
    end

    def incomplete_installation?
      existing_filesystem.incomplete_installation?
    end

    def equal_arch?(arch1, arch2)
      # bsc#288201
      return true if arch1 == arch2

      # bsc#249791
      ["ppc", "ppc64"].include?(arch1) && ["ppc", "ppc64"].include?(arch2)
    end

    def first_fstab_entry_matches?
      first_entry = fstab.entries.first

      fstab_entry_matches?(first_entry, filesystem)
    end

    # It returns true if the given fstab entry matches with the given device
    # filesystem or false if not.
    #
    # @param entry [Y2Storage::SimpleEtcFstabEntry]
    # @param filesystem [Y2Storage::Filesystems::BlkFilesystem]
    #
    # @return [Boolean]
    def fstab_entry_match?(entry, filesystem)
      spec = entry.fstab_device
      id, value = spec.include?("=") ? spec.split('=') : ["", spec]
      id.downcase!

      if ["label", "uuid"].include?(id)
        dev_string = id == "label" ? filesystem.label : filesystem.uuid
        return true if dev_string == value

        log.warn("Device does not match fstab (#{id}): #{dev_string} vs. #{value}")
        false
      else
        name_matches_device?(value, filesystem.blk_devices.first)
      end
    end

    # Checks whether the given device name matches the given block device
    #
    # @param name [String] can be a kernel name like "/dev/sda1" or any symbolic
    #   link below the /dev directory
    # @param blk_dev [Y2Storage::BlkDevice]
    # @return [Boolean]
    def name_matches_device?(name, blk_dev)
      found = devicegraph.find_by_any_name(name)
      return true if found && found.sid == blk_dev.sid

      log.warn("Device does not match fstab (name): #{blk_dev.name} not equivalent to #{name}")
      false
    end

    def devicegraph
      filesystem.devicegraph
    end
  end
end
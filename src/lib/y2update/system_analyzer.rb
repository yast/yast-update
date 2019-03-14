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

Yast.import "Linuxrc"
Yast.import "ModuleLoading"
Yast.import "UI"

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

        filesystems_data << read_filesystem_data(filesystems)
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


    end





        # Check a root partition and return map with information (see
        # variable rootPartitions).
        def CheckPartition(filesystem)
          device = filesystem.blk_devices[0]
          p_dev = device.name

          freshman = {
            valid:  false,
            name:   "unknown",
            arch:   "unknown",
            label:  filesystem.label,
            fs:     filesystem.type.to_sym,
            fstype: device_type(device)
          }

          # possible root FS
          if filesystem.type.root_ok? || filesystem.type.legacy_root?
            mount_type = filesystem.type.to_s

            error_message = nil
            log.debug("Running RunFSCKonJFS with mount_type: #{mount_type} and device: #{p_dev}")
            if !(
                error_message_ref = arg_ref(error_message);
                _RunFSCKonJFS_result = RunFSCKonJFS(
                  mount_type,
                  p_dev,
                  error_message_ref
                );
                error_message = error_message_ref.value;
                _RunFSCKonJFS_result
              )
              freshman[:valid] = false
              log.debug("Returning not valid partition: #{freshman}")
              return freshman
            end

            # mustn't be empty and must be modular
            if mount_type != "" && !NON_MODULAR_FS.include?(mount_type)
              log.debug("Calling modprobe #{mount_type}")
              SCR.Execute(path(".target.modprobe"), mount_type, "")
            end

            # storage-ng: not sure if we need to introduce something equivalent
    =begin
            log.debug("Removing #{p_dev}")
            Storage.RemoveDmMapsTo(p_dev)
    =end

            # mount (read-only) partition to Installation::destdir
            log.debug("Mounting #{[p_dev, Installation.destdir, Installation.mountlog].inspect}")
            mount =
              SCR.Execute(
                path(".target.mount"),
                [p_dev, Installation.destdir, Installation.mountlog],
                "-o ro"
              )

            if Convert.to_boolean(mount)
              # Is this a root partition, does /etc/fstab exists?
              log.debug("Checking /etc/fstab in #{Installation.destdir}")
              if Ops.greater_than(
                  SCR.Read(
                    path(".target.size"),
                    Ops.add(Installation.destdir, "/etc/fstab")
                  ),
                  0
                )
                Builtins.y2milestone("found fstab on %1", p_dev)

                fstab = []
                crtab = []

                fstab_ref = arg_ref(fstab)
                crtab_ref = arg_ref(crtab)
                read_fstab_and_cryptotab(fstab_ref, crtab_ref, p_dev)
                fstab = fstab_ref.value
                crtab = crtab_ref.value
                Update.GetProductName

                fstab = Builtins.filter(fstab) do |p|
                  Ops.get_string(p, "file", "") == "/"
                end

                if Builtins.size(Ops.get_string(fstab, [0, "spec"], "")) == 0
                  Builtins.y2warning("Cannot find / entry in fstab %1", fstab)
                end

                freshman[:valid] = fstab_entry_matches?(fstab[0], filesystem)

                if Mode.autoinst
                  # we dont care about the other checks in autoinstallation
                  SCR.Execute(path(".target.umount"), Installation.destdir)
                  return deep_copy(freshman)
                end

                freshman[:valid] = false if !Update.IsProductSupportedForUpgrade

                # Get installed release name
                # TRANSLATORS: label for an unknown installed system
                freshman[:name] = Update.installed_product || _("Unknown")
                Builtins.y2debug("release: %1", freshman[:name])

                # Right architecture?
                freshman[:arch] = GetArchOfELF(Installation.destdir + "/bin/bash")
                instsys_arch = GetArchOfELF("/bin/bash")

                # `arch_valid, see bugzilla #288201
                # installed /bin/bash and the one from inst-sys are matching
                if freshman[:arch] == instsys_arch
                  Builtins.y2milestone("Architecture (%1) is valid", instsys_arch)
                  freshman[:arch_valid] = true

                  # both are PPC, bugzilla #249791
                elsif ["ppc", "ppc64"].include?(freshman[:arch]) &&
                    ["ppc", "ppc64"].include?(instsys_arch)
                  Builtins.y2milestone(
                    "Architecture for partition %1 is %2, upgrading %3",
                    p_dev, freshman[:arch], instsys_arch
                  )
                  freshman[:arch_valid] = true

                  # Architecture is not matching
                else
                  Builtins.y2milestone(
                    "Architecture for partition %1 is %2, upgrading %3",
                    p_dev, freshman[:arch], instsys_arch
                  )
                  freshman[:arch_valid] = false
                end

                if !freshman[:arch_valid]
                  log.info "Architecture is not valid -> the whole partition is not valid"
                  freshman[:valid] = false
                end

                if IncompleteInstallationDetected(Installation.destdir)
                  log.info "Incomplete installation detected, partition is not valid"
                  freshman[:valid] = false
                end

                Builtins.y2milestone(
                  "Partition is valid: %1, arch is valid: %2",
                  Ops.get_boolean(freshman, :valid, false),
                  Ops.get_boolean(freshman, :arch_valid, false)
                )
              end

              # unmount partition
              SCR.Execute(path(".target.umount"), Installation.destdir)
            end
          end

          log.info("#{filesystem} #{freshman}")

          deep_copy(freshman)
        end



















  end
end
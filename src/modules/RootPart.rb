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

# Module:  RootPart.ycp
#
# Authors:  Arvin Schnell <arvin@suse.de>
#
# Purpose:  Responsible for searching of root partitions and
#    mounting of target partitions.

require "yast"
require "yast2/fs_snapshot"
require "yast2/fs_snapshot_store"
require "y2storage"

require "fileutils"
require "nokogiri"

module Yast
  class RootPartClass < Module
    include Logger
    NON_MODULAR_FS = ["devtmpfs", "none", "proc", "sysfs"].freeze

    # filesystems which support the "norecovery" mount options
    NORECOVERY_FS = [:btrfs, :ext3, :ext4, :xfs].freeze

    def main
      Yast.import "UI"

      textdomain "update"

      Yast.import "Directory"
      Yast.import "Mode"
      Yast.import "Linuxrc"
      Yast.import "Popup"
      Yast.import "ModuleLoading"
      Yast.import "Update"
      Yast.import "FileUtils"
      Yast.import "Arch"
      Yast.import "String"
      Yast.import "Installation"
      Yast.import "Report"
      Yast.import "Label"
      Yast.import "Stage"
      Yast.import "Wizard"

      # Selected root partition for the update or boot.
      @selectedRootPartition = ""

      # FATE #301844, to find out that a system for update has been changed
      @previousRootPartition = ""

      # Map of all root partitions (key) and information map (value).
      # The information map contains the keys `valid, `name and `arch.
      @rootPartitions = {}

      # Number of valid root partitions.
      @numberOfValidRootPartitions = 0

      # Show all partitions (not only root partitions) in the dialog.
      @showAllPartitions = false

      # Did we search for root partitions
      @didSearchForRootPartitions = false

      # We successfully mounted the target partitions
      @targetOk = false

      # Did we try to mount the target partitions?
      @did_try_mount_partitions = false

      @already_checked_jfs_partitions = []

      # List of mounted partitions, activated swap partitions and loop devices.
      # Amongst other things used for reversing action if mode is changed from
      # update to new installation or if root partition for update is changed.
      # The order of the list if of paramount importance.
      #
      # Each item is list [string value, string type [, string device]] where:
      #
      # Keys/values are:
      #
      #   `type     The type, one of "mount", "swap" or "crypt".
      #
      #   `device   The device.
      #
      #   `mntpt    The mount point, only for `type = "mount".  Does not
      #             include Installation::destdir.
      @activated = []
    end

    # Returns currently activated partitions.
    #
    # @return [Array<Hash{Symbol => String>}] activated
    def GetActivated
      deep_copy(@activated)
    end

    def Mounted
      Ops.greater_than(Builtins.size(@activated), 0)
    end

    # Get the key what of the selected root partition.
    def GetInfoOfSelected(what)
      i = Ops.get(@rootPartitions, @selectedRootPartition, {})

      # TRANSLATORS: label - name of system to update was not found
      return Ops.get_locale(i, what, _("Unknown")) if what != :name

      # Name is known
      if Ops.get_string(i, what, "") != ""
        Ops.get_string(i, what, "")

        # Linux partition, but no root FS found
      elsif Builtins.contains(
        FileSystems.possible_root_fs,
        Ops.get_symbol(i, :fs, :nil)
      )
        # TRANSLATORS: label - name of system to update
        _("Unknown Linux System")

        # Non-Linux
      else
        # TRANSLATORS: label - name of system to update
        _("Non-Linux System")
      end
    end

    # Set the selected root partition to some valid one. Only
    # make sense if the number of valid root partition is one.
    def SetSelectedToValid
      @selectedRootPartition = ""
      Builtins.foreach(@rootPartitions) do |p, i|
        if Ops.get_boolean(i, :valid, false) && @selectedRootPartition == ""
          @selectedRootPartition = p
        end
      end

      nil
    end

    def RemoveFromTargetMap
      target_map = Storage.GetTargetMap
      tmp = Builtins.filter(@activated) do |e|
        Ops.get_string(e, :type, "") == "mount"
      end
      Builtins.foreach(tmp) do |e|
        target_map = Storage.SetPartitionData(
          target_map,
          Ops.get_string(e, :device, ""),
          "mount",
          ""
        )
      end
      Storage.SetTargetMap(target_map)

      nil
    end

    # Unmount all mounted partitions, deactivate swaps, detach loopback
    # devices. Uses list activated to make actions in reverse order.
    # @param keeep_in_target Do not remove mounts from targetmap
    # @return [void]
    def UnmountPartitions(keep_in_target)
      Builtins.y2milestone("UnmountPartitions: %1", keep_in_target)

      @did_try_mount_partitions = false

      Builtins.foreach(@activated) do |info|
        Builtins.y2milestone("Unmounting %1", info)
        type = Ops.get_string(info, :type, "")
        if type != ""
          case type
          when "mount"
            file = Ops.add(
              Installation.destdir,
              Ops.get_string(info, :mntpt, "")
            )
            if !Convert.to_boolean(SCR.Execute(path(".target.umount"), file))
              # TRANSLATORS: error report, %1 is device (eg. /dev/hda1)
              Report.Error(
                Builtins.sformat(
                  _(
                    "Cannot unmount partition %1.\n" \
                    "\n" \
                    "It is currently in use. If the partition stays mounted,\n" \
                    "the data may be lost. Unmount the partition manually\n" \
                    "or restart your computer.\n"
                  ),
                  file
                )
              )
            end
          when "swap"
            device = Ops.get_string(info, :device, "")
            # FIXME? is it safe?
            if SCR.Execute(
              path(".target.bash"),
              Ops.add("/sbin/swapoff ", device)
            ) != 0
              Builtins.y2error("Cannot deactivate swap %1", device)
            end
          when "crypt"
            dmname = Ops.get_string(info, :device, "")
            dmname = Ops.add(
              "cr_",
              Builtins.substring(
                dmname,
                Ops.add(Builtins.findlastof(dmname, "/"), 1)
              )
            )
            # FIXME? is it safe?
            if WFM.Execute(
              path(".local.bash"),
              Ops.add("cryptsetup remove ", dmname)
            ) != 0
              Builtins.y2error("Cannot remove dm device %1", dmname)
            end
          end
        end
      end

      # now remove the mount points in the target system
      remove_mount_points(staging) unless keep_in_target

      # clear activated list
      @activated = []

      nil
    end

    # Add information about mounted partition to internal list.
    # @param [Hash{Symbol => String}] partinfo partinfo has to be list with exactly two strings,
    # see description of list "activated"
    # @return [void]
    def AddMountedPartition(partinfo)
      partinfo = deep_copy(partinfo)
      @activated = Builtins.prepend(@activated, partinfo)
      Builtins.y2debug("adding %1 yields %2", partinfo, @activated)

      nil
    end

    # Check the filesystem of a partition.
    def FSCKPartition(partition)
      detected_fs = fstype_for_device(probed, partition)
      if detected_fs == "ext2"
        # TRANSLATORS: label, %1 is partition
        out = Builtins.sformat(_("Checking partition %1"), partition)
        UI.OpenDialog(Opt(:decorated), Label(out))

        Builtins.y2milestone("command: /sbin/e2fsck -y %1", partition)
        SCR.Execute(
          path(".target.bash"),
          Ops.add("/sbin/e2fsck -y ", partition)
        )

        UI.CloseDialog
      end

      nil
    end

    # @param [String] headline (optional; to disable, use "")
    # @param [String] question
    # @param string button (true)
    # @param string button (false)
    # @param [String] details (hidden under [Details] button; optional; to disable, use "")
    def AnyQuestionAnyButtonsDetails(headline, question, button_yes, button_no, details)
      has_details = true
      has_details = false if details == "" || details.nil?

      has_heading = true
      has_heading = false if headline == "" || headline.nil?

      heading = has_heading ? VBox(Left(Heading(headline))) : Empty()

      popup_def = Left(Label(question))

      details_checkbox = if has_details
        VBox(
          VSpacing(1),
          # TRANSLATORS: check box label
          Left(CheckBox(Id(:details), Opt(:notify), _("Show &Details"), false))
        )
      else
        Empty()
      end

      popup_buttons = VBox(
        VSpacing(1),
        HBox(
          HSpacing(8),
          PushButton(Id(:yes), button_yes),
          VSpacing(2),
          PushButton(Id(:cancel), button_no),
          HSpacing(8)
        ),
        VSpacing(0.5)
      )

      UI.OpenDialog(
        Opt(:decorated),
        VSquash(
          VBox(
            heading,
            popup_def,
            Left(Opt(:hstretch), ReplacePoint(Id(:rp_details), Empty())),
            details_checkbox,
            popup_buttons
          )
        )
      )
      UI.SetFocus(Id(:yes))

      ret = nil

      loop do
        userinput = UI.UserInput

        case userinput
        when :yes
          ret = true
          break
        when :details
          curr_status = Convert.to_boolean(UI.QueryWidget(Id(:details), :Value))

          if curr_status == false
            UI.ReplaceWidget(Id(:rp_details), Empty())
          else
            UI.ReplaceWidget(
              Id(:rp_details),
              MinSize(
                60,
                10,
                RichText(Id(:details_text), Opt(:plainText, :hstretch), details)
              )
            )
          end
        else
          ret = false
          break
        end
      end

      UI.CloseDialog

      ret
    end

    # Function checks the device and returns whether it is OK or not.
    # The read-only FS check is performed for jfs only and only one for
    # one device.
    #
    # @param [String] mount_type "jfs", "ext2" or "reiser"
    # @param [String] device, such as /dev/hda3 or /dev/sda8
    # @param [string &] error_message (a reference to string)
    # @return [Boolean] if successfull or if user forces it
    def RunFSCKonJFS(mount_type, device, error_message)
      # #176292, run fsck before jfs is mounted
      if mount_type == "jfs" && device != ""
        if Builtins.contains(@already_checked_jfs_partitions, device)
          Builtins.y2milestone("Device %1 has been already checked...", device)
          return true
        end

        UI.OpenDialog(
          # TRANSLATORS: progress status, %1 is a device name, e.g. "/dev/sda1"
          Label(Builtins.sformat(_("Checking file system on %1..."), device))
        )

        Builtins.y2milestone("Running fsck on %1", device)
        # -n == Check read only, make no changes to the file system.
        cmd = Convert.to_map(
          SCR.Execute(
            path(".target.bash_output"),
            Builtins.sformat("fsck.jfs -n %1", device)
          )
        )

        UI.CloseDialog

        # failed
        if Ops.get(cmd, "exit") == 0
          # add device into the list of already checked partitions (with exit status 0);
          @already_checked_jfs_partitions = Builtins.add(
            @already_checked_jfs_partitions,
            device
          )
          Builtins.y2milestone("Result: %1", cmd)
          return true
        else
          Builtins.y2error("Result: %1", cmd)
          error_message.value = Builtins.tostring(Ops.get(cmd, "stderr"))

          details = ""
          if Ops.get_string(cmd, "stdout", "") != ""
            details = Ops.add(details, Ops.get_string(cmd, "stdout", ""))
          end
          if Ops.get_string(cmd, "stderr", "") != ""
            details = Ops.add(
              Ops.add((details == "") ? "" : "\n", details),
              Ops.get_string(cmd, "stderr", "")
            )
          end

          return AnyQuestionAnyButtonsDetails(
            # TRANSLATORS: popup headline
            _("File System Check Failed"),
            Builtins.sformat(
              # TRANSLATORS: popup question (continue/cancel dialog)
              # %1 is a device name such as /dev/hda5
              _(
                "The file system check of device %1 has failed.\n" \
                "\n" \
                "Do you want to continue mounting the device?\n"
              ),
              device
            ),
            Label.ContinueButton,
            # TRANSLATORS: button label
            _("&Skip Mounting"),
            details
          )
          # succeeded
        end
      end

      true
    end

    # Mount partition on specified mount point
    # @param mount_point [String] path to mount the partition at
    # @param device [String] device to mount, in the format of the first field of fstab
    # @param mount_type [String] filesystem type to be specified while mounting
    # @return [String] nil on success, error description on fail
    def MountPartition(mount_point, device, mount_type, fsopts = "")
      if mount_type == ""

        # Note that "device" comes from the unmodified fstab entry so it can be
        # something like 'UUID=2f61fdb9-f82a-4052-8610-1eb090b82098'.
        mount_type = fstype_for_device(probed, device) || ""
      end

      # #223878, do not call modprobe with empty mount_type
      if mount_type == ""
        Builtins.y2warning("Unknown filesystem, skipping modprobe...")
        # #211916, sysfs, proc are not modular
      elsif !NON_MODULAR_FS.include?(mount_type)
        # #167976, was broken with "-t ", modprobe before adding it
        Builtins.y2milestone("Calling 'modprobe %1'", mount_type)
        SCR.Execute(path(".target.modprobe"), mount_type, "")
      else
        Builtins.y2milestone(
          "FS type %1 is not modular, skipping modprobe...",
          mount_type
        )
      end

      error_message = nil
      if !(
          error_message_ref = arg_ref(error_message)
          _RunFSCKonJFS_result = RunFSCKonJFS(
            mount_type,
            device,
            error_message_ref
          )
          error_message = error_message_ref.value
          _RunFSCKonJFS_result
        )
        return error_message
      end

      mnt_opts = cleaned_mount_options(fsopts)

      mnt_opts = "-o " + mnt_opts unless mnt_opts.empty?

      mnt_opts << " -t #{mount_type}" if mount_type != ""

      Builtins.y2milestone("mount options '#{mnt_opts}'")
      Builtins.y2milestone("mount #{mnt_opts} #{device} #{Installation.destdir + mount_point}")

      ret = Convert.to_boolean(
        SCR.Execute(
          path(".target.mount"),
          [
            device,
            Ops.add(Installation.destdir, mount_point),
            Installation.mountlog
          ],
          mnt_opts
        )
      )
      ret ? nil : SCR.Read(path(".target.string"), Installation.mountlog)
    end

    # Check filesystem on a partition and mount the partition on specified mount
    #  point
    # @param [String] mount_point string mount point to monut the partition at
    # @param [String] device string device to mount
    # @param [String] mount_type string filesystem type to be specified while mounting
    # @return [String] nil on success, error description on fail
    def FsckAndMount(mount_point, device, mount_type, mntopts = "")
      FSCKPartition(device)

      ret = MountPartition(mount_point, device, mount_type, mntopts)

      if ret.nil?
        AddMountedPartition(
          type: "mount", device: device, mntpt: mount_point
        )
      end

      Builtins.y2milestone(
        "mounting (%1, %2, %3) yields %4",
        Ops.add(Installation.destdir, mount_point),
        device,
        mount_type,
        ret
      )

      ret
    end

    #  Check that the root filesystem in fstab has the correct device.
    def check_root_device(_partition, fstab, found_partition)
      fstab = deep_copy(fstab)
      tmp = Builtins.filter(fstab) do |entry|
        Ops.get_string(entry, "file", "") == "/"
      end

      if Builtins.size(tmp) != 1
        Builtins.y2error("not exactly one root partition found in fstab")
        found_partition.value = "none"
        return false
      end

      true
    end

    # Find a mount point in fstab
    # @param [list <map> &] fstab a list of fstab entries
    # @param [String] mountpoint string a mount point to find
    # @return [String] the found partition
    def FindPartitionInFstab(fstab, mountpoint)
      # Removing the "/" and then adding it again in the comparison below looks
      # weird, but let's don't change this ancient code too much.
      mountpoint = mountpoint.chomp("/")

      tmp = fstab.value.select do |entry|
        file = entry.fetch("file", "")
        mntops = entry.fetch("mntops", "")

        # Discard Btrfs subvolumes, they are not really a separate device
        if mntops.include?("subvol=")
          log.info "FindPartitionInFstab: #{file} subvolume ignored"
          next false
        end

        file == mountpoint || file == mountpoint + "/"
      end
      return nil if tmp.size.zero?

      tmp.first.fetch("spec", "")
    end

    def update_mount_options(options)
      if Builtins.regexpmatch(options, "^(.*,)?hotplug(,.*)?$")
        return Builtins.regexpsub(
          options,
          "^(.*,)?hotplug(,.*)?$",
          "\\1nofail\\2"
        )
      end
      options
    end

    # Register a new fstab agent and read the configuration
    # from Installation::destdir
    def readFsTab(fstab)
      fstab_file = Ops.add(Installation.destdir, "/etc/fstab")

      if FileUtils.Exists(fstab_file)
        # NOTE: this is a copy from etc_fstab.scr file (yast2.rpm),
        # keep the files in sync!
        SCR.RegisterAgent(
          path(".target.etc.fstab"),
          term(
            :ag_anyagent,
            term(
              :Description,
              term(:File, fstab_file),
              # tab and space is a workaround for white space only lines (bsc#1030425)
              "#\n\t ",	# Comment
              false, # read-only
              term(
                :List,
                term(
                  :Tuple,
                  term(:spec, term(:String, "^\t ")),
                  term(:Separator, "\t "),
                  term(:file, term(:String, "^\t ")),
                  term(:Separator, "\t "),
                  term(:vfstype, term(:String, "^\t ")),
                  term(:Separator, "\t "),
                  term(:mntops, term(:String, "^ \t\n")),
                  term(:Optional, term(:Whitespace)),
                  term(:Optional, term(:freq, term(:Number))),
                  term(:Optional, term(:Whitespace)),
                  term(:Optional, term(:passno, term(:Number))),
                  term(:Optional, term(:Whitespace)),
                  term(:Optional, term(:the_rest, term(:String, "^\n")))
                ),
                "\n"
              )
            )
          )
        )

        fstab.value = Convert.convert(
          SCR.Read(path(".target.etc.fstab")),
          from: "any",
          to:   "list <map>"
        )

        SCR.UnregisterAgent(path(".target.etc.fstab"))
      else
        Builtins.y2error("No such file %1. Not using fstab.", fstab_file)
      end

      nil
    end

    def FstabUsesKernelDeviceNameForHarddisks(fstab)
      fstab = deep_copy(fstab)
      # We just want to check the use of kernel device names for hard
      # disks. Not for e.g. BIOS RAIDs or LVM logical volumes.

      # Since we are looking at device names of hard disks that may no
      # longer exist all we have at hand is the name.

      !Builtins.find(fstab) do |line|
        spec = Ops.get_string(line, "spec", "error")
        next true if Builtins.regexpmatch(spec, "^/dev/sd[a-z]+[0-9]+$")
        next true if Builtins.regexpmatch(spec, "^/dev/hd[a-z]+[0-9]+$")
        next true if Builtins.regexpmatch(spec, "^/dev/dasd[a-z]+[0-9]+$")

        false
      end.nil?
    end

    # Reads FSTab and CryptoTab and fills fstab and crtab got as parameters.
    # Uses Installation::destdir as the base mount point.
    #
    # @param list <map> ('pointer' to) fstab
    # @param list <map> ('pointer' to) crtab
    # @param string root device
    def read_fstab_and_cryptotab(fstab, crtab, _root_device_current)
      # /etc/cryptotab was deprecated in favor of /etc/crypttab
      #
      # crypttab file is processed by storage-ng, see {#MountPartitions}.
      crtab.value = []

      if Stage.initial
        fstab_ref = arg_ref(fstab.value)
        readFsTab(fstab_ref)
        fstab.value = fstab_ref.value
      else
        fstab.value = Convert.convert(
          SCR.Read(path(".etc.fstab")),
          from: "any",
          to:   "list <map>"
        )
      end

      true
    end

    # bugzilla #258563
    def CheckBootSize(_bootpart)
      min_suggested_bootsize = 65536
      min_suggested_bootsize = 204800 if Arch.ia64

      bootsize = nil

      cmd = Builtins.sformat(
        "/bin/df --portability --no-sync -k '%1/boot' | grep -v '^Filesystem' | sed 's/[ ]\\+/ /g'",
        Installation.destdir
      )
      bootsizeout = Convert.to_map(
        SCR.Execute(path(".target.bash_output"), cmd)
      )

      if Ops.get_integer(bootsizeout, "exit", -1) == 0
        scriptout = Builtins.splitstring(
          Ops.get_string(bootsizeout, "stdout", ""),
          " "
        )
        Builtins.y2milestone("Scriptout: %1", scriptout)
        bootsize = Builtins.tointeger(Ops.get(scriptout, 1, "0"))
      else
        Builtins.y2error("Error: '%1' -> %2", cmd, bootsizeout)
      end

      if bootsize.nil? || bootsize == 0
        Builtins.y2error(
          "Cannot find out bootpart size: %1",
          Installation.destdir
        )
        return true
      end

      Builtins.y2milestone(
        "Boot size is: %1 recommended min.: %2",
        bootsize,
        min_suggested_bootsize
      )

      # Size of the /boot partition is satisfactory
      return true if Ops.greater_or_equal(bootsize, min_suggested_bootsize)

      current_bs = Ops.divide(bootsize, 1024)
      suggested_bs = Ops.divide(min_suggested_bootsize, 1024)

      cont = Popup.ContinueCancelHeadline(
        # TRANSLATORS: a popup headline
        _("Warning"),
        # TRANSLATORS: error message,
        # %1 is replaced with the current /boot partition size
        # %2 with the recommended size
        Builtins.sformat(
          _(
            "Your /boot partition is too small (%1 MB).\n" \
            "We recommend a size of no less than %2 MB or else the new Kernel may not fit.\n" \
            "It is safer to either enlarge the partition\n" \
            "or not use a /boot partition at all.\n" \
            "\n" \
            "Do you want to continue updating the current system?\n"
          ),
          current_bs,
          suggested_bs
        )
      )

      if cont
        Builtins.y2warning(
          "User decided to continue despite small a /boot partition"
        )
        true
      else
        Builtins.y2milestone(
          "User decided not to continue with small /boot partition"
        )
        false
      end
    end

    # Mount /sys /proc and the like inside Installation.destdir
    # @return [void]
    def mount_specials_in_destdir
      # mount sysfs first
      if MountPartition("/sys", "sysfs", "sysfs").nil?
        AddMountedPartition(
          type: "mount", device: "sysfs", mntpt: "/sys"
        )
      end

      if MountPartition("/proc", "proc", "proc").nil?
        AddMountedPartition(
          type: "mount", device: "proc", mntpt: "/proc"
        )
      end

      # to have devices like /dev/cdrom and /dev/urandom in the chroot
      if MountPartition("/dev", "devtmpfs", "devtmpfs").nil?
        AddMountedPartition(
          type: "mount", device: "devtmpfs", mntpt: "/dev"
        )
      end

      # bind-mount /run into chroot (bsc#1152530)
      if MountPartition("/run", "/run", "none", "bind").nil?
        AddMountedPartition(
          type: "mount", device: "none", mntpt: "/run"
        )
      end

      efivars_path = "/sys/firmware/efi/efivars"
      return unless ::File.exist?(efivars_path)
      return unless MountPartition(efivars_path, "efivarfs", "efivarfs").nil?

      AddMountedPartition(type: "mount", device: "efivarfs", mntpt: efivars_path)
    end

    def MountFSTab(fstab, _message)
      fstab = deep_copy(fstab)

      mount_specials_in_destdir

      success = true

      return success if Mode.test

      fstab.each do |mounts|
        vfstype = mounts.fetch("vfstype", "")
        mntops  = mounts.fetch("mntops", "")
        spec    = mounts.fetch("spec", "")
        fspath  = mounts.fetch("file", "")

        if mount_regular_fstab_entry?(mounts)
          log.info("mounting #{spec} to #{fspath}")

          mount_type = ""
          mount_type = vfstype if vfstype == "proc"

          loop do
            # An encryption device might be probed with a name that does not match with the name
            # indicated in the fstab file. For example, when the fstab entry is:
            #
            #   /dev/mapper/cr_home   /home   ext4  defaults  0   0
            #
            # and that encryption device was probed as /dev/mapper/cr-auto-1.
            #
            # In that case, to mount /dev/mapper/cr_home would fail because there is not a device
            # in the inst-sys with such name. To avoid possible failures when mounting the fstab
            # device, the safest device name is used instead, that is, UUID= format or its uuid
            # udev name, see {#safest_device_name}.
            mount_error = FsckAndMount(fspath, safest_device_name(spec), mount_type, mntops)
            break if mount_error.nil?

            mount_path = "#{Installation.destdir}/#{fspath}"
            log.error("mounting #{spec} (type #{mount_type}) on #{mount_path} failed")

            action = mount_failed_action(spec, mount_error)

            case action
            when :cont
              break
            when :cancel
              success = false
              break
            when :cmd
              fspath, spec, mount_type = user_mount_options(fspath, spec, mount_type)
            end
          end

          success = false if (fspath == "/boot" || fspath == "/boot/") && !CheckBootSize(spec)
        elsif vfstype == "swap" && fspath == "swap"
          log.info("mounting #{spec} to #{fspath}")

          command = "/sbin/swapon "
          if spec != ""
            # swap-partition
            command = Ops.add(command, spec)

            # run /sbin/swapon
            ret_from_shell = Convert.to_integer(
              SCR.Execute(path(".target.bash"), command)
            )
            if ret_from_shell == 0
              AddMountedPartition(type: "swap", device: spec)
            else
              log.error("swapon failed: #{command}")
            end
          end
        end
      end

      success
    end

    # Displays a warning dialog to the suer when mount failed
    #
    # Apart from informing, it lets on the user the next actions: to ignore the error and continue,
    # to check and/or specify the mount options, or to abort the update.
    #
    # FIXME: this dialog should live in its own class. However, extracting it to a method
    # looks like a good compromise in the context of the PBI it has been addressed. So please,
    # feel free to make it a first-class citizen in future changes.
    #
    # @param spec [String]
    # @param error [String] the error returned by {#FsckAndMount}
    # @return [Symbol] the action chosen by the user, namely
    #   :cont if decides to continue because the partition is not necessary for the update
    #   :cmd when wants to check or specify the mount options
    #   :cancel whether goes for aborting the update process
    def mount_failed_action(spec, error)
      UI.OpenDialog(
        VBox(
          Label(
            Builtins.sformat(
              # TRANSLATORS: label in a popup, %1 is device (eg. /dev/hda1),
              # %2 is output of the 'mount' command
              _(
                "The partition %1 could not be mounted.\n" \
                "\n" \
                "%2\n" \
                "\n" \
                "If you are sure that the partition is not necessary for the\n" \
                "update (not a system partition), click Continue.\n" \
                "To check or fix the mount options, click Specify Mount Options.\n" \
                "To abort the update, click Cancel.\n"
              ),
              spec,
              error
            )
          ),
          VSpacing(1),
          HBox(
            PushButton(Id(:cont), Label.ContinueButton),
            # TRANSLATORS: button label
            PushButton(Id(:cmd), _("&Specify Mount Options")),
            PushButton(Id(:cancel), Label.CancelButton)
          )
        )
      )

      action = UI.UserInput.to_sym

      UI.CloseDialog

      action
    end

    # Displays the Mount Options dialog to the user
    #
    # FIXME: this dialog should live in its own class. However, extracting it to a method
    # looks like a good compromise in the context of the PBI it has been addressed. So please,
    # feel free to make it a first-class citizen in future changes.
    #
    # @param fspath [String] the filesytem path
    # @param spec [String]
    # @param mount_type [String]
    #
    # @return [Array<(String, String, String)>] an array holding the current (if the user
    #   cancels) or the new (when user accepts) values for fspath, spec, and mount_type
    def user_mount_options(fspath, spec, mount_type)
      UI.OpenDialog(
        VBox(
          # TRANSLATORS: dialog heading
          Heading(_("Mount Options")),
          VSpacing(0.6),
          # TRANSLATORS: input field
          TextEntry(Id(:mp), _("&Mount Point"), fspath),
          VSpacing(0.4),
          # TRANSLATORS: input field
          TextEntry(Id(:device), _("&Device"), spec),
          VSpacing(0.4),
          # TRANSLATORS: input field
          TextEntry(Id(:fs), _("&File System\n(empty for autodetection)"), mount_type),
          VSpacing(1),
          HBox(
            PushButton(Id(:ok), Label.OKButton),
            PushButton(Id(:cancel), Label.CancelButton)
          )
        )
      )

      action = UI.UserInput.to_sym

      if action == :ok
        fspath     = UI.QueryWidget(Id(:mp), :Value).to_s
        spec       = UI.QueryWidget(Id(:device), :Value).to_s
        mount_type = UI.QueryWidget(Id(:fs), :Value).to_s
      end

      UI.CloseDialog

      [fspath, spec, mount_type]
    end

    def has_pam_mount
      # detect pam_mount encrypted homes
      pam_mount_path = Installation.destdir + "/etc/security/pam_mount.conf.xml"
      return false unless File.exist? pam_mount_path

      doc = Nokogiri::XML(File.read(pam_mount_path), &:strict)

      Builtins.y2milestone("Detected pam_mount.conf, checking existence of encrypted home dirs")
      volumes = doc.xpath("/pam_mount/volume")
      Builtins.y2milestone("Detected encrypted volumes: %1", volumes.inspect)
      !(volumes.nil? || volumes.empty?)
    end

    # Mounting root-partition; reading fstab and mounting read partitions
    def MountPartitions(root_device_current)
      Builtins.y2milestone("mount partitions: %1", root_device_current)

      return true if @did_try_mount_partitions

      @did_try_mount_partitions = true

      success = true

      # TRANSLATORS: popup message, %1 will be replace with the name of the logfile
      message = Builtins.sformat(
        _(
          "Partitions could not be mounted.\n" \
          "\n" \
          "Check the log file %1."
        ),
        Ops.add(Directory.logdir, "/y2log")
      )
      Builtins.y2milestone("selected partition: %1", root_device_current)

      ret_bool = true

      fstab = []
      crtab = []

      # Mount selected root partition to Installation::destdir
      ret_bool = nil == FsckAndMount("/", root_device_current, "") if !Mode.test

      if ret_bool
        fstab_ref = arg_ref(fstab)
        crtab_ref = arg_ref(crtab)
        read_fstab_and_cryptotab(fstab_ref, crtab_ref, root_device_current)
        fstab = fstab_ref.value

        # Encryption names indicated in the crypttab file are stored in its correspondig encryption
        # device to make possible to find a device by using the name specified in a fstab file,
        # (bsc#1094963).
        #
        # For example, when fstab has:
        #
        #   /dev/disk/by-id/dm-name-cr_home / auto 0 0
        #
        # and the fstab device is searched by that name:
        #
        #   devicegraph.find_by_any_name("/dev/disk/by-id/dm-name-cr_home")
        #
        # The proper encryption device could be found if there is a encrypttion device where
        #
        #   encryption.crypttab_name  #=> "cr_home"
        crypttab_path = File.join(Installation.destdir, "/etc/crypttab")
        crypttab = Y2Storage::Crypttab.new(crypttab_path)
        crypttab.save_encryption_names(probed)

        Update.GetProductName

        if FstabUsesKernelDeviceNameForHarddisks(fstab)
          Builtins.y2warning(
            "fstab on %1 uses kernel device name for hard disks",
            root_device_current
          )
          warning = Builtins.sformat(
            # TRANSLATORS: warning popup
            _(
              "Some partitions in the system on %1 are mounted by kernel-device name. This is\n" \
              "not reliable for the update since kernel-device names are unfortunately not\n" \
              "persistent. It is strongly recommended to start the old system and change the\n" \
              "mount-by method to any other method for all partitions."
            ),
            root_device_current
          )
          if Mode.autoupgrade
            Popup.TimedWarning(warning, 10)
          else
            Popup.Warning(warning)
          end
        end

        if has_pam_mount
          warning = Builtins.sformat(
            # TRANSLATORS: warning popup
            _(
              "Some home directories in the system on %1 are encrypted. This release does not\n" \
              "support cryptconfig any longer and those home directories " \
              "will not be accessible\n" \
              "after upgrade. In order to access these home directories, " \
              "they need to be decrypted\n" \
              "before performing upgrade.\n" \
              "You can consider encrypting whole volume via LUKS."
            ),
            root_device_current
          )
          Report.Warning(warning)
        end

        if Builtins.size(fstab) == 0
          Builtins.y2error("no or empty fstab found!")
          # TRANSLATORS: error message
          message = _("No fstab found.")
          success = false
        else
          tmp = ""

          if (tmp_ref = arg_ref(tmp))
            check_root_device(
              root_device_current,
              fstab,
              tmp_ref
            )

            Builtins.y2milestone("fstab %1", fstab)

            legacy_filesystems =
              Y2Storage::Filesystems::Type.legacy_home_filesystems.map(&:to_s)

            legacy_entries = fstab.select { |e| legacy_filesystems.include?(e["vfstype"]) }

            # Removed ReiserFS support for system upgrade (fate#323394).
            if !legacy_entries.empty?
              message =
                Builtins.sformat(
                  # TRANSLATORS: popup message
                  _("The mount points listed below are using legacy filesystems " \
                    "that are not supported anymore:\n\n%1\n\n"                    \
                    "Before upgrade you should migrate all "                 \
                    "your data to another filesystem.\n"),
                  legacy_entries.map { |e| "#{e["file"]} (#{e["vfstype"]})" }.join("\n")
                )

              success = false
            elsif !(
                message_ref = arg_ref(message)
                _MountFSTab_result = MountFSTab(fstab, message_ref)
                message = message_ref.value
                _MountFSTab_result
              )
              success = false
            end
          else
            Builtins.y2error("fstab has wrong root device!")

            # TRANSLATORS: Error message, where %{root} and %{tmp} are replaced by
            # device names (e.g., /dev/sda1 and /dev/sda2).
            message = format(
              _("The root partition in /etc/fstab has an invalid root device.\n" \
                "It is currently mounted as %{root} but listed as %{tmp}."),
              root: root_device_current,
              tmp:  tmp
            )

            success = false
          end
        end
      else
        Builtins.y2error(
          "Could not mount root '%1' to '%2'",
          root_device_current,
          Installation.destdir
        )
        success = false
      end

      Builtins.y2milestone(
        "MountPartition (%1) = %2",
        root_device_current,
        success
      )
      Builtins.y2milestone("activated %1", @activated)

      if success
        # enter the mount points of the newly mounted partitions
        update_staging!
        create_pre_snapshot
        Update.clean_backup
        create_backup
        inject_intsys_files
      else
        Popup.Message(message)

        # some mount failed, unmount all mounted fs
        UnmountPartitions(false)
        @did_try_mount_partitions = true
      end

      success
    end

    RESOLV_CONF = "/etc/resolv.conf".freeze

    # known configuration files that are changed during update, so we need to
    # backup them to restore if something goes wrong (bnc#882039)
    BACKUP_DIRS = {
      # use a number prefix to set the execution order
      "0100-sw_mgmt"     => [
        "/var/lib/rpm",
        "/etc/zypp/repos.d",
        "/etc/zypp/services.d",
        "/etc/zypp/credentials.d"
      ],
      # this should be restored as the very last one, after restoring the original
      # resolv.conf the network might not work properly in the chroot
      "0999-resolv_conf" => [
        RESOLV_CONF
      ]
    }.freeze

    def create_backup
      BACKUP_DIRS.each_pair do |name, paths|
        Update.create_backup(name, paths)
      end
    end

    # inject the required files from the inst-sys to the chroot so
    # the network connection works for the chrooted scripts
    def inject_intsys_files
      # the original file is backed up and restored later
      target = File.join(Installation.destdir, RESOLV_CONF)
      # use copy entry as we need to remove_destination 5th param in case of symlink to dynamic
      # resolver like systemd-resolver and some configuration of network manager. So we not modify
      # symlink target and instead just replace symlink with our file that can resolve and from
      # backup we later restore original symlink.
      ::FileUtils.copy_entry(RESOLV_CONF, target, false, false, true) if File.exist?(RESOLV_CONF)
    rescue Errno::EPERM => e
      # just log a warning when rewriting the file is not permitted,
      # e.g. it has the immutable flag set (bsc#1096142)
      # assume that the user locked content works properly
      log.warn("Cannot update #{target}, keeping the original content, #{e.class}: #{e}")
    end

    # Get architecture of an elf file.
    def GetArchOfELF(filename)
      bash_out = Convert.to_map(
        SCR.Execute(
          path(".target.bash_output"),
          Ops.add(Ops.add(Directory.ybindir, "/elf-arch "), filename)
        )
      )
      return "unknown" if Ops.get_integer(bash_out, "exit", 1) != 0

      Builtins.deletechars(Ops.get_string(bash_out, "stdout", "unknown"), "\n")
    end

    # Checks the partition whether it contains an incomplete installation.
    #
    # @see BNC #441919
    # @param string system mounted to directory
    # @return [Boolean] true if incomplete
    def IncompleteInstallationDetected(mounted_to)
      # by default, installation is complete
      ret = false

      Builtins.foreach([Installation.run_yast_at_boot]) do |check_this|
        check_this = Builtins.sformat("%1/%2", mounted_to, check_this)
        if FileUtils.Exists(check_this) == true
          Builtins.y2milestone(
            "File %1 exists, installation is incomplete",
            check_this
          )
          ret = true
          raise Break
        end
      end

      ret
    end

    # This is the closest equivalent we have in storage-ng
    def device_type(device)
      if device.is?(:partition)
        device.id.to_human_string
      elsif device.is?(:lvm_lv)
        "LV"
      end
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
            error_message_ref = arg_ref(error_message)
            _RunFSCKonJFS_result = RunFSCKonJFS(
              mount_type,
              p_dev,
              error_message_ref
            )
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

        mount_options = ["ro"]
        mount_options << "norecovery" if NORECOVERY_FS.include?(freshman[:fs])

        # mount (read-only) partition to Installation::destdir
        log.info "Mounting #{p_dev} with options #{mount_options}"
        mount =
          SCR.Execute(
            path(".target.mount"),
            [p_dev, Installation.destdir, Installation.mountlog],
            "-o #{mount_options.join(",")}"
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
            Update.GetProductName

            fstab = Builtins.filter(fstab) do |p|
              Ops.get_string(p, "file", "") == "/"
            end

            if Builtins.size(Ops.get_string(fstab, [0, "spec"], "")) == 0
              Builtins.y2warning("Cannot find / entry in fstab %1", fstab)
            end

            freshman[:valid] = fstab_entry_matches?(fstab[0], filesystem) if fstab[0]

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

    # Find all valid root partitions and place the result in rootPartitions.
    # The partitions are mounted and unmounted again (to Installation::destdir).
    # Loads a bunch of kernel modules.
    # @return [void]
    def FindRootPartitions
      log.debug("Finding root partitions")

      return if @didSearchForRootPartitions

      modules_to_load = {
        "xfs"          => "XFS",
        "ext3"         => "Ext3",
        "ext4"         => "Ext4",
        "btrfs"        => "BtrFS",
        "raid0"        => "Raid 0",
        "raid1"        => "Raid 1",
        "raid5"        => "Raid 5",
        "raid6"        => "Raid 6",
        "raid10"       => "Raid 10",
        "dm-multipath" => "Multipath",
        "dm-mod"       => "DM",
        "dm-snapshot"  => "DM Snapshot"
      }

      modules_to_load.each do |module_to_load, show_name|
        ModuleLoading.Load(module_to_load, "", "Linux", show_name, Linuxrc.manual, true)
      end

      #  Storage::ActivateEvms();

      # prepare progress-bar
      if UI.WidgetExists(Id("search_progress"))
        UI.ReplaceWidget(
          Id("search_progress"),
          ProgressBar(
            Id("search_pb"),
            # TRANSLATORS: progress bar label
            _("Evaluating root partition. One moment please..."),
            100,
            0
          )
        )
      end

      @rootPartitions = {}
      @numberOfValidRootPartitions = 0

      # all formatted partitions and lvs on all devices
      filesystems = probed.blk_filesystems.reject { |fs| fs.type.is?(:swap) }

      filesystems.each_with_index do |fs, counter|
        if UI.WidgetExists(Id("search_progress"))
          percent = 100 * (counter + (1 / filesystems.size))
          UI.ChangeWidget(Id("search_pb"), :Value, percent)
        end

        log.debug("Checking filesystem: #{fs}")
        freshman = CheckPartition(fs)

        @rootPartitions[fs.blk_devices[0].name] = freshman
        @numberOfValidRootPartitions += 1 if freshman[:valid]
      end

      # 100%
      UI.ChangeWidget(Id("search_pb"), :Value, 100) if UI.WidgetExists(Id("search_progress"))

      @didSearchForRootPartitions = true

      Builtins.y2milestone("rootPartitions: %1", @rootPartitions)

      nil
    end

    def GetDistroArch
      GetArchOfELF("/bin/bash")
    end

    def mount_target
      UI.OpenDialog(
        Opt(:decorated),
        # TRANSLATORS: intermediate popup while mounting partitions
        Label(_("Mounting partitions. One moment please..."))
      )

      tmp = MountPartitions(@selectedRootPartition)
      # sleep (500);

      UI.CloseDialog

      tmp
    end

    def Detect
      if !@didSearchForRootPartitions
        Wizard.SetContents(
          # TRANSLATORS: dialog caption
          _("Searching for Available Systems"),
          VBox(ReplacePoint(Id("search_progress"), Empty())),
          "",
          false,
          false
        )

        FindRootPartitions()

        @selectedRootPartition = ""
        Builtins.y2milestone("Detected root partitions: %1", @rootPartitions)
      end

      nil
    end

    IGNORED_OPTIONS = [
      "ro", # in installation do not mount anything RO
      "defaults", # special defaults options in fstab
      /^locale=.*$/ # avoid locale for NTFS
    ].freeze

    def cleaned_mount_options(mount_options)
      elements = mount_options.split(",")
      # rubocop:disable Style/CaseEquality
      # disabled to use feature that `===` match against regexp
      elements.delete_if { |e| IGNORED_OPTIONS.any? { |o| o === e } }
      # rubocop:enable Style/CaseEquality
      elements.join(",")
    end

    # Load saved data from given Hash
    #
    # @param [Hash<String => Object>]
    def load_saved(data)
      @activated             = data["activated"]  || []
      @selectedRootPartition = data["selected"]   || ""
      @previousRootPartition = data["previous"]   || ""
      @rootPartitions        = data["partitions"] || {}
    end

    publish variable: :selectedRootPartition, type: "string"
    publish variable: :previousRootPartition, type: "string"
    publish variable: :rootPartitions, type: "map <string, map>"
    publish variable: :numberOfValidRootPartitions, type: "integer"
    publish variable: :showAllPartitions, type: "boolean"
    publish variable: :didSearchForRootPartitions, type: "boolean"
    publish variable: :targetOk, type: "boolean"
    publish variable: :did_try_mount_partitions, type: "boolean"
    publish function: :GetActivated, type: "list <map <symbol, string>> ()"
    publish function: :Mounted, type: "boolean ()"
    publish function: :GetInfoOfSelected, type: "string (symbol)"
    publish function: :SetSelectedToValid, type: "void ()"
    publish function: :UnmountPartitions, type: "void (boolean)"
    publish function: :AnyQuestionAnyButtonsDetails,
      type:     "boolean (string, string, string, string, string)"
    publish function: :MountPartitions, type: "boolean (string)"
    publish function: :IncompleteInstallationDetected, type: "boolean (string)"
    publish function: :FindRootPartitions, type: "void ()"
    publish function: :GetDistroArch, type: "string ()"
    publish function: :mount_target, type: "boolean ()"
    publish function: :Detect, type: "void ()"

  private

    def probed
      Y2Storage::StorageManager.instance.probed
    end

    def staging
      Y2Storage::StorageManager.instance.staging
    end

    # Remove mount point from all filesystems
    #
    # @param devicegraph [Y2Storage::Devicegraph]
    def remove_mount_points(devicegraph)
      devicegraph.filesystems.each do |filesystem|
        filesystem.remove_mount_point unless filesystem.mount_point.nil?
      end
    end

    # It returns true if the given fstab entry matches with the given device
    # filesystem or false if not.
    #
    # @param entry [String]
    # @param filesystem [Y2Storage::Filesystems::BlkFilesystem]
    #
    # @return [Boolean]
    def fstab_entry_matches?(entry, filesystem)
      spec = entry["spec"]
      id, value = spec.include?("=") ? spec.split("=") : ["", spec]
      id.downcase!

      if ["label", "uuid"].include?(id)
        dev_string = (id == "label") ? filesystem.label : filesystem.uuid
        return true if dev_string == value

        log.warn("Device does not match fstab (#{id}): #{dev_string} vs. #{value}")
        false
      else
        name_matches_device?(value, filesystem.blk_devices[0])
      end
    end

    # Checks whether the given device name matches the given block device
    #
    # @param name [String] can be a kernel name like "/dev/sda1" or any symbolic
    #   link below the /dev directory
    # @param blk_dev [Y2Storage::BlkDevice]
    # @return [Boolean]
    def name_matches_device?(name, blk_dev)
      found = staging.find_by_any_name(name)
      return true if found && found.sid == blk_dev.sid

      log.warn("Device does not match fstab (name): #{blk_dev.name} not equivalent to #{name}")
      false
    end

    # The only value of this seems to be for yast-bootloader to locate the
    # root & boot devices.
    def update_staging!
      log.info "start update_staging"

      partitions = @activated.select { |entry| entry[:type] == "mount" }
      update_staging_partitions!(partitions)

      partitions = @activated.select { |entry| entry[:type] == "swap" }
      update_staging_partitions!(partitions, "swap")

      log.info "end update_staging"
    end

    def update_staging_partitions!(activated_partitions, mountpoint = nil)
      activated_partitions.each do |activated_partition|
        dev = activated_partition[:device]
        mntpt = mountpoint || activated_partition[:mntpt]
        update_staging_filesystem!(dev, mntpt)
      end
    end

    def update_staging_filesystem!(name, mountpoint)
      log.info "Setting partition data: Device: #{name}, MountPoint: #{mountpoint}"

      # Take into account that 'name' comes straight out of
      # /etc/fstab and might look like 'UUID=2f61fdb9-f82a-4052-8610-1eb090b82098'.
      mount_by = Y2Storage::Filesystems::MountByType.from_fstab_spec(name)
      return unless mount_by

      filesystem = fs_by_devicename(staging, name)
      return unless filesystem

      filesystem.mount_path = mountpoint
      filesystem.mount_point.mount_by = mount_by
    end

    # FIXME
    #
    # It would make more sense to return the fs type object directly but atm it
    # integrates better with existing code to return a string.
    #
    # Look up filesystem type for a device.
    #
    # Return nil if there's no such device or device doesn't have a filesystem.
    #
    # @param devicegraph [Devicegraph]
    # @param device_spec [String] fs_spec field of one entry from fstab
    #
    # @return [String, nil]
    #
    def fstype_for_device(devicegraph, device_spec)
      fs = fs_by_devicename(devicegraph, device_spec)
      fs.type.to_s if fs
    end

    # Look up filesystem object with matching device name, as specified in
    # fstab.
    #
    # Return nil if there's no such device or the device doesn't have a
    # filesystem.
    #
    # @param devicegraph [Devicegraph]
    # @param device_spec [String] fs_spec field of one entry from fstab
    # @return [Y2Storage::Filesystems::Base, nil]
    #
    def fs_by_devicename(devicegraph, device_spec)
      fs = devicegraph.filesystems.find { |f| f.match_fstab_spec?(device_spec) }
      # If the previous search returned nil, there is still a last chance to
      # find the device. Maybe 'device_spec' is one of the udev names discarded
      # by libstorage-ng
      fs ||= fs_by_udev_lookup(devicegraph, device_spec)

      # log which devicegraph we operate on
      graph = "?"
      graph = "probed" if devicegraph.equal?(probed)
      if devicegraph.equal?(staging)
        graph = "staging#" + Y2Storage::StorageManager.instance.staging_revision.to_s
      end
      log.info("fs_by_devicename(#{graph}, #{device_spec}) = #{"sid#" + fs.sid.to_s if fs}")

      fs
    end

    # Finds a filesystem by udev name, using a direct lookup in the system
    # (i.e. going beyond the udev names recognized by libstorage-ng) if needed
    #
    # @param devicegraph [Devicegraph]
    # @param name [String] full udev name
    # @return [Y2Storage::Filesystems::BlkFilesystem, nil]
    def fs_by_udev_lookup(devicegraph, name)
      dev = devicegraph.find_by_any_name(name)
      return nil if dev.nil? || !dev.respond_to?(:filesystem)

      dev.filesystem
    end

    # Safest device name to perform the mount action
    #
    # It will be the udev uuid name (e.g., /dev/disk/by-uuid/111-222-333) when the device
    # spec has not UUID= format.
    #
    # @see udev_uuid
    #
    # @example
    #
    #   safest_device_name("UUID=111-222-333")    #=> "UUID=111-222-333"
    #   safest_device_name("/dev/mapper/cr_home") #=> "/dev/disk/by-uuid/111-222-333"
    #
    # @param device_spec [String] e.g., "UUID=111-222-333", "/dev/sda2", "/dev/mapper/cr_home"
    # @return [String] safest device name, e.g., "/dev/disk/by-uuid/111-222-333"
    def safest_device_name(device_spec)
      return device_spec if device_spec.start_with?("UUID=")

      udev_uuid(device_spec) || device_spec
    end

    # Finds a device and returns its udev uuid name
    #
    # @param device_spec [String] e.g., "UUID=111-222-333", "/dev/sda2", "/dev/mapper/cr_home"
    # @return [String, nil] uuid name (e.g., "/dev/disk/by-uuid/111-222-333") or nil if the
    #   device is not found.
    def udev_uuid(device_spec)
      filesystem = fs_by_devicename(probed, device_spec)
      return nil if filesystem.nil?

      device = filesystem.blk_devices.first
      device.udev_full_uuid
    end

    # @see #mount_regular_fstab_entry?(
    ALLOWED_FS = [
      "ext",
      "ext2",
      "ext3",
      "ext4",
      "btrfs",
      "jfs",
      "xfs",
      "hpfs",
      "vfat",
      "auto"
    ].freeze
    private_constant :ALLOWED_FS

    # Whether a given fstab entry should be mounted by {#MountFSTab}
    #
    # @param entry [Hash] fstab entry
    # @return [Boolean]
    def mount_regular_fstab_entry?(entry)
      vfstype = entry.fetch("vfstype", "")
      mntops = entry.fetch("mntops", "")
      path = entry.fetch("file", "")

      return false if path == "/"
      return false unless ALLOWED_FS.include?(vfstype)
      return false if mntops.include?("noauto")

      true
    end

    # Creates a pre-update snapshot and stores its number
    #
    # If something goes wrong, it reports the problem to the user.
    def create_pre_snapshot
      return unless Yast2::FsSnapshot.configured?

      # as of bsc #1092757 snapshot descriptions are not translated
      snapshot = Yast2::FsSnapshot.create_pre("before update", cleanup: :number, important: true)
      Yast2::FsSnapshotStore.save("update", snapshot.number)
    rescue Yast2::SnapshotCreationFailed => e
      log.error("Error creating a pre-update snapshot: #{e}")
      Yast::Report.Error(
        # TRANSLATORS: error message
        _("A pre-update snapshot could not be created. You can continue with the \n" \
          "installation, but beware that you cannot roll back to a pre-update state \n" \
          "unless you have created a snapshot manually.")
      )
    end
  end

  RootPart = RootPartClass.new
  RootPart.main
end

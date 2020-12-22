#!/usr/bin/env rspec

require_relative "test_helper"

Yast.import "RootPart"

describe Yast::RootPart do
  describe "#MountVarIfRequired" do
    before do
      stub_storage(scenario)
      # Mock the system lookup executed as last resort when the devicegraph
      # doesn't contain the searched information
      allow(Y2Storage::BlkDevice).to receive(:find_by_any_name)
    end

    let(:scenario) { "two-disks-two-btrfs.xml" }

    let(:fstab_sda1) do
      [
        {
          "file"=>"/", "mntops"=>"defaults", "vfstype"=>"btrfs",
          "spec"=> root_spec
        },
        {
          "file"=>"/lib/machines", "mntops"=>"subvol=/@/lib/machines", "vfstype"=>"btrfs",
          "spec"=> root_spec
        },
        {
          "file"=>"/var", "mntops"=>"subvol=/@/var", "vfstype"=>"btrfs",
          "spec"=> root_spec
        },
        {
          "file"=>"swap", "mntops"=>"defaults", "vfstype"=>"swap",
          "spec"=>"/dev/disk/by-uuid/a62e32ec-f58d-4bff-941b-6fb9ea45c016"
        }
      ]
    end

    let(:fstab_sda2) do
      [
        {
          "file"=>"/", "mntops"=>"defaults", "vfstype"=>"btrfs",
          "spec"=> root_spec
        },
        {
          "file"=>"/usr/local", "mntops"=>"subvol=/@/usr/local", "vfstype"=>"btrfs",
          "spec"=> root_spec
        },
        {
          "file"=>"/tmp", "mntops"=>"subvol=/@/tmp", "vfstype"=>"btrfs",
          "spec"=> root_spec
        },
        {
          "file"=>"/.snapshots", "mntops"=>"subvol=/@/.snapshots", "vfstype"=>"btrfs",
          "spec"=> root_spec
        },
        {
          "file"=>"swap", "mntops"=>"defaults", "vfstype"=>"swap",
          "spec"=>"UUID=a62e32ec-f58d-4bff-941b-6fb9ea45c016"
        }
      ]
    end

    RSpec.shared_examples "mounting result" do
      context "and mounting /var fails with an error message" do
        before do
          allow(subject).to receive(:FsckAndMount).with("/var", any_args)
            .and_return "an error"
        end

        it "returns a string including the device and the error " do
          result = subject.MountVarIfRequired(fstab, root_device, false)
          expect(result).to be_a(String)
          expect(result).to include("an error")
          expect(result).to include(var_device)
        end
      end

      context "and mounting /var succeeds" do
        before do
          allow(subject).to receive(:FsckAndMount).with("/var", any_args).and_return nil
        end

        it "returns nil" do
          expect(subject.MountVarIfRequired(fstab, root_device, false)).to be_nil
        end
      end
    end

    context "if there is no separate partition" do
      context "and no @/var subvolume" do
        let(:fstab) { fstab_sda2 }
        let(:root_device) { "/dev/sda2" }
        let(:root_spec) { "UUID=d6e5c710-3067-48de-8363-433e54a9d0b5" }

        it "does not try to mount /var" do
          expect(subject).to_not receive(:FsckAndMount)
          subject.MountVarIfRequired(fstab, root_device, false)
        end

        it "returns nil" do
          expect(subject.MountVarIfRequired(fstab, root_device, false)).to be_nil
        end
      end

      context "and there is a @/var subvolume" do
        let(:fstab) { fstab_sda1 }
        let(:root_device) { "/dev/sda1" }
        let(:root_spec) { "UUID=0a0ebfa7-e1a8-45f2-ad53-495e192fcc8d" }

        # The old code did not support Btrfs properly, so it mounted the /var
        # subvolume as a partition, which produced big breakage.
        it "does not try to mount /var" do
          expect(subject).to_not receive(:FsckAndMount)
          subject.MountVarIfRequired(fstab, root_device, false)
        end

        it "returns nil" do
          expect(subject.MountVarIfRequired(fstab, root_device, false)).to be_nil
        end
      end
    end

    context "if /var is a separate partition" do
      let(:fstab) do
        fstab_sda2 + [
          {
            "file"=>"/var", "mntops"=>"defaults", "vfstype"=>"xfs",
            "spec"=> var_spec
          }
        ]
      end

      context "that was mounted by UUID" do
        let(:root_device) { "/dev/sda2" }
        let(:root_spec) { "UUID=d6e5c710-3067-48de-8363-433e54a9d0b5" }

        let(:var_spec) { "UUID=c9510dc7-fb50-4f7b-bd84-886965c821f6" }
        let(:var_device) { var_spec }

        it "tries to mount /var by its UUID" do
          expect(subject).to receive(:FsckAndMount).with("/var", var_device, "")
          subject.MountVarIfRequired(fstab, root_device, false)
        end

        include_examples "mounting result"
      end

      context "that was mounted by kernel device name" do
        # Let's simulate the situation in which the disk used to have another name
        let(:root_spec) { "/dev/sdb2" }
        let(:root_device) { "/dev/sda2" }

        context "and is in the same disk than /" do
          let(:var_spec) { "/dev/sdb4" }
          let(:var_device) { "/dev/sda4" }

          it "tries to mount /var by its adapted device name" do
            expect(subject).to receive(:FsckAndMount).with("/var", var_device, "")
            subject.MountVarIfRequired(fstab, root_device, false)
          end

          include_examples "mounting result"
        end

        context "and is in a different disk than / (two disks in total)" do
          let(:var_spec) { "/dev/sda1" }
          let(:var_device) { "/dev/sdb1" }

          it "tries to mount /var by its adapted device name" do
            expect(subject).to receive(:FsckAndMount).with("/var", var_device, "")
            subject.MountVarIfRequired(fstab, root_device, false)
          end

          include_examples "mounting result"
        end
      end
    end

    context "if /var is a separate LVM logical volume" do
      let(:scenario) { "trivial-lvm.yml" }

      let(:fstab) do
        fstab_sda2 + [
          {
            "file"=>"/var", "mntops"=>"defaults", "vfstype"=>"xfs",
            "spec"=> var_spec
          }
        ]
      end

      context "that was mounted by UUID" do
        let(:root_device) { "/dev/vg0/root" }
        let(:root_spec) { "/dev/disk/by-uuid/5a0a-3387" }

        let(:var_spec) { "/dev/disk/by-uuid/4b85-3de0" }
        let(:var_device) { var_spec }

        it "tries to mount /var by its UUID" do
          expect(subject).to receive(:FsckAndMount).with("/var", var_device, "")
          subject.MountVarIfRequired(fstab, root_device, false)
        end

        include_examples "mounting result"
      end

      context "that was mounted by kernel device name" do
        let(:root_spec) { "/dev/vg0/root" }
        let(:root_device) { "/dev/vg0/root" }

        context "and the LV is not longer there" do
          let(:var_spec) { "/dev/vg0/none" }
          let(:var_device) { "/dev/vg0/none" }

          it "tries to mount /var by its old device name" do
            expect(subject).to receive(:FsckAndMount).with("/var", var_device, "")
            subject.MountVarIfRequired(fstab, root_device, false)
          end

          include_examples "mounting result"
        end

        context "and the LV is still there" do
          let(:var_spec) { "/dev/vg0/var" }
          let(:var_device) { "/dev/vg0/var" }

          it "tries to mount /var by its device name" do
            expect(subject).to receive(:FsckAndMount).with("/var", var_device, "")
            subject.MountVarIfRequired(fstab, root_device, false)
          end

          include_examples "mounting result"
        end
      end
    end
  end

  describe "#mount_specials_in_destdir" do
    before do
      allow(subject).to receive(:MountPartition).and_return(nil)
      allow(subject).to receive(:AddMountedPartition)
    end

    it "does not crash" do
      expect { subject.mount_specials_in_destdir }.to_not raise_error
    end
  end

  describe "#MountFSTab" do
    before do
      stub_storage(scenario)
      # Mock the system lookup executed as last resort when the devicegraph
      # doesn't contain the searched information
      allow(Y2Storage::BlkDevice).to receive(:find_by_any_name)
    end

    let(:scenario) { "two-disks-two-btrfs.xml" }

    let(:fstab) do
      [
        {
          "file"=>"/home", "mntops"=>"defaults", "vfstype"=>"ext4", "spec"=> device_spec
        }
      ]
    end

    let(:device_spec) { nil }

    it "mounts /dev, /proc, /run, and /sys" do
      allow(subject).to receive(:MountPartition)
      allow(subject).to receive(:AddMountedPartition)

      ["/dev", "/proc", "/run", "/sys"].each do |d|
        expect(subject).to receive(:MountPartition).with(d, anything, anything, any_args)
      end

      # call with empty list to only test the /dev, /proc, /run, and /sys mounting
      fstab = []
      subject.MountFSTab(fstab, "")
    end

    context "when the device spec has UUID= format" do
      let(:device_spec) { "UUID=111-222-333" }

      it "tries to mount by using UUID= spec" do
        expect(subject).to receive(:FsckAndMount)
          .with("/home", "UUID=111-222-333", anything, anything)

        subject.MountFSTab(fstab, "")
      end
    end

    context "when the device spec does not have UUID= format" do
      context "and a device with such spec is not found" do
        let(:device_spec) { "/dev/sdc1" }

        it "tries to mount by using the given device spec" do
          expect(subject).to receive(:FsckAndMount)
            .with("/home", "/dev/sdc1", anything, anything)

          subject.MountFSTab(fstab, "")
        end
      end

      context "and a device with such spec is found" do
        let(:device_spec) { "/dev/sda2" }

        it "tries to mount by using its udev uuid name" do
          expect(subject).to receive(:FsckAndMount)
            .with("/home", "/dev/disk/by-uuid/d6e5c710-3067-48de-8363-433e54a9d0b5", anything, anything)

          subject.MountFSTab(fstab, "")
        end
      end
    end
  end

  describe "#inject_intsys_files" do
    before do
      allow(Yast::Installation).to receive(:destdir).and_return("/mnt")
    end

    context "resolv.conf exists in inst-sys" do
      before do
        expect(File).to receive(:exist?).with("/etc/resolv.conf").and_return(true)
        allow(FileUtils).to receive(:copy_entry)
      end

      it "copies the resolv.conf from inst-sys to the target" do
        expect(FileUtils).to receive(:copy_entry).with("/etc/resolv.conf", "/mnt/etc/resolv.conf", false, false, true)
        subject.inject_intsys_files
      end

      # (bsc#1096142)
      it "does not crash on the EPERM exception" do
        expect(FileUtils).to receive(:copy_entry).with("/etc/resolv.conf", "/mnt/etc/resolv.conf", false, false, true) \
          .and_raise(Errno::EPERM)
        expect { subject.inject_intsys_files }.to_not raise_error
      end
    end

    context "resolv.conf does not exist in inst-sys" do
      before do
        expect(File).to receive(:exist?).with("/etc/resolv.conf").and_return(false)
      end

      it "does not copy the resolv.conf" do
        expect(FileUtils).to_not receive(:copy_entry).with("/etc/resolv.conf", "/mnt/etc/resolv.conf", false, false, true)
        subject.inject_intsys_files
      end
    end
  end
end

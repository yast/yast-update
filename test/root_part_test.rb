#!/usr/bin/env rspec

require_relative "test_helper"

Yast.import "RootPart"

describe Yast::RootPart do
  describe "#mount_specials_in_destdir" do
    before do
      allow(subject).to receive(:MountPartition).and_return(nil)
      allow(subject).to receive(:AddMountedPartition)
      expect(File).to receive(:exist?).and_return(true)
      allow(Yast::SCR).to receive(:Execute).with(Yast::Path, Array, String)
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

      # avoid test on real FS
      allow(::File).to receive(:exist?).and_return(false)
    end

    let(:scenario) { "two-disks-two-btrfs.xml" }

    let(:fstab) do
      [
        {
          "file" => "/home", "mntops" => "defaults", "vfstype" => "ext4", "spec" => device_spec
        }
      ]
    end

    let(:device_spec) { nil }

    it "mounts /dev, /proc, /run, and /sys" do
      allow(File).to receive(:exist?).with("/sys/firmware/efi/efivars").and_return(false)
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
            .with("/home", "/dev/disk/by-uuid/d6e5c710-3067-48de-8363-433e54a9d0b5",
              anything, anything)

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
        expect(FileUtils).to receive(:copy_entry)
          .with("/etc/resolv.conf", "/mnt/etc/resolv.conf", false, false, true)
        subject.inject_intsys_files
      end

      # (bsc#1096142)
      it "does not crash on the EPERM exception" do
        expect(FileUtils).to receive(:copy_entry)
          .with("/etc/resolv.conf", "/mnt/etc/resolv.conf", false, false, true)
          .and_raise(Errno::EPERM)
        expect { subject.inject_intsys_files }.to_not raise_error
      end
    end

    context "resolv.conf does not exist in inst-sys" do
      before do
        expect(File).to receive(:exist?).with("/etc/resolv.conf").and_return(false)
      end

      it "does not copy the resolv.conf" do
        expect(FileUtils).to_not receive(:copy_entry)
          .with("/etc/resolv.conf", "/mnt/etc/resolv.conf", false, false, true)
        subject.inject_intsys_files
      end
    end
  end

  describe "#has_pam_mount" do
    context "pam_mount.conf.xml does not exist" do
      before do
        allow(File).to receive(:exist?).and_return(false)
      end

      it "returns false" do
        expect(subject.has_pam_mount).to eq false
      end
    end

    context "pam_mount.conf.xml exists and does not contain any volumes" do
      before do
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_return(<<~CONTENT
          <pam_mount>
          </pam_mount>
        CONTENT
                                                )
      end

      it "returns false" do
        expect(subject.has_pam_mount).to eq false
      end
    end

    context "pam_mount.conf.xml exists and contains volumes" do
      before do
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_return(<<~CONTENT
          <pam_mount>
            <!-- Generic encrypted partition example -->
            <volume user="USERNAME" fstype="auto" path="/dev/sdaX" mountpoint="/home" options="fsck,noatime" />
             <!-- Example using CIFS -->
            <volume
              fstype="cifs"
              server="server.example.com"
              path="share_name"
              mountpoint="~/mnt/share_name"
              uid="10000-19999"
              options="sec=krb5i,vers=3.0,cruid=%(USERUID)"
            />
            <mkmountpoint enable="1" remove="true" />
           </pam_mount>
        CONTENT
                                                )
      end

      it "returns true" do
        expect(subject.has_pam_mount).to eq true
      end
    end
  end
end

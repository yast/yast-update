#!/usr/bin/env rspec

require_relative "test_helper"

Yast.import "RootPart"

describe Yast::RootPart do
  describe "#MountFSTab" do
    before do
      stub_storage(scenario)
      allow(subject).to receive(:FsckAndMount)
      allow(Yast::UI).to receive(:OpenDialog)
      allow(Yast::UI).to receive(:UserInput).twice.and_return(user_input, :ok)
      # Mock the system lookup executed as last resort when the devicegraph
      # doesn't contain the searched information
      allow(Y2Storage::BlkDevice).to receive(:find_by_any_name)
    end

    let(:user_input) { :cancel }

    let(:message) { Yast.arg_ref("") }

    let(:scenario) { "two-disks-two-btrfs.xml" }

    let(:fstab_sda1) do
      [
        {
          "file" => "/", "mntops" => "defaults", "vfstype" => "btrfs",
          "spec" => root_spec
        },
        {
          "file" => "/lib/machines", "mntops" => "subvol=/@/lib/machines", "vfstype" => "btrfs",
          "spec" => root_spec
        },
        {
          "file" => "/var", "mntops" => "subvol=/@/var", "vfstype" => "btrfs",
          "spec" => root_spec
        },
        {
          "file" => "swap", "mntops" => "defaults", "vfstype" => "swap",
          "spec" => "/dev/disk/by-uuid/a62e32ec-f58d-4bff-941b-6fb9ea45c016"
        }
      ]
    end

    let(:fstab_sda2) do
      [
        {
          "file" => "/", "mntops" => "defaults", "vfstype" => "btrfs",
          "spec" => root_spec
        },
        {
          "file" => "/usr/local", "mntops" => "subvol=/@/usr/local", "vfstype" => "btrfs",
          "spec" => root_spec
        },
        {
          "file" => "/tmp", "mntops" => "subvol=/@/tmp", "vfstype" => "btrfs",
          "spec" => root_spec
        },
        {
          "file" => "/.snapshots", "mntops" => "subvol=/@/.snapshots", "vfstype" => "btrfs",
          "spec" => root_spec
        },
        {
          "file" => "swap", "mntops" => "defaults", "vfstype" => "swap",
          "spec" => "UUID=a62e32ec-f58d-4bff-941b-6fb9ea45c016"
        }
      ]
    end

    context "mounting /var" do
      before do
        allow(subject).to receive(:FsckAndMount).with("/var", any_args)
          .and_return(fsck_and_mount_result)
      end

      RSpec.shared_examples "mounting /var fails" do
        context "fails with an error message" do
          let(:fsck_and_mount_result) { "an error while mounting" }

          it "displays a dialog informing the user about it" do
            expect(Yast::UI).to receive(:OpenDialog) do |content|
              label = content.nested_find { |e| e.is_a?(Yast::Term) && e.value == :Label }
              text = label.params.first

              expect(text).to include(var_spec)
              expect(text).to include("could not be mounted")
              expect(text).to include(fsck_and_mount_result)
            end

            subject.MountFSTab(fstab, message)
          end

          context "but the user decides to continue anyway" do
            let(:user_input) { :cont }

            it "returns true" do
              result = subject.MountFSTab(fstab, message) 
              expect(result).to eq(true)
            end
          end

          context "and the user decides to cancel" do
            let(:user_input) { :cancel }

            it "returns false" do
              result = subject.MountFSTab(fstab, message) 
              expect(result).to eq(false)
            end
          end

          context "and the user decides to check or fix the mount options" do
            let(:user_input) { :cmd }

            it "displays the mount options dialog" do
              expect(Yast::UI).to receive(:OpenDialog) # Let's skip the first dialog
              expect(Yast::UI).to receive(:OpenDialog) do |content|
                heading = content.nested_find { |e| e.is_a?(Yast::Term) && e.value == :Heading }
                text = heading.params.first

                expect(text).to include("Mount Options")
              end

              subject.MountFSTab(fstab, message)
            end
          end
        end
      end

      RSpec.shared_examples "mounting /var succeeds" do
        context "and mounting /var succeeds" do
          let(:fsck_and_mount_result) { nil }

          it "returns true" do
            result = subject.MountFSTab(fstab, message) 
            expect(result).to eq(true)
          end
        end
      end

      context "if there is no separate partition" do
        context "and no @/var subvolume" do
          let(:fstab) { fstab_sda2 }
          let(:root_spec) { "UUID=d6e5c710-3067-48de-8363-433e54a9d0b5" }

          pending
        end

        context "and there is a @/var subvolume" do
          let(:fstab) { fstab_sda1 }
          let(:root_spec) { "UUID=0a0ebfa7-e1a8-45f2-ad53-495e192fcc8d" }

          pending
        end
      end

      context "if /var is a separate partition" do
        let(:fstab) do
          fstab_sda2 + [
            {
              "file" => "/var", "mntops" => "defaults", "vfstype" => "xfs",
              "spec" => var_spec
            }
          ]
        end

        context "and the device is found in the system" do
          let(:root_spec) { "UUID=d6e5c710-3067-48de-8363-433e54a9d0b5" }

          let(:var_spec) { "UUID=c9510dc7-fb50-4f7b-bd84-886965c821f6" }

          include_examples "mounting /var succeeds"
        end

        context "and the device is not found in the system" do
          let(:root_spec) { "/dev/sda2" }

          let(:var_spec) { "/dev/sdc1" }

          include_examples "mounting /var fails"
         end
      end

      context "if /var is a separate LVM logical volume" do
        let(:scenario) { "trivial-lvm.yml" }

        let(:fstab) do
          fstab_sda2 + [
            {
              "file" => "/var", "mntops" => "defaults", "vfstype" => "xfs",
              "spec" => var_spec
            }
          ]
        end

        context "and the LVM logical volume is found in the system" do
          let(:root_spec) { "/dev/vg0/root" }

          let(:var_spec) { "/dev/disk/by-uuid/4b85-3de0" }

          include_examples "mounting /var succeeds"
        end

        context "and the LVM logical volume is not found in the system" do
          let(:root_spec) { "/dev/vg0/root" }

          let(:var_spec) { "/dev/disk/by-uuid/not-found" }

          include_examples "mounting /var fails"
        end
      end
    end
  end

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

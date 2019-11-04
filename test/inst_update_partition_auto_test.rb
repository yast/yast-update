#!/usr/bin/env rspec

require_relative "test_helper"
require "update/clients/inst_update_partition_auto"

Yast.import "RootPart"
Yast.import "Update"
Yast.import "Installation"

describe Yast::InstUpdatePartitionAutoClient do

  describe "#main" do
    before do
      stub_root_part
      stub_const("Yast::FileSystems", double)
      allow(Yast::Update)
      allow(Yast::Installation).to receive(:destdir).and_return("/mnt")
      allow(Yast::Report).to receive(:error)
      allow(Yast::Pkg).to receive(:TargetInitializeOptions)
      allow(Yast::Pkg).to receive(:TargetFinish)
      allow(Yast::Pkg).to receive(:TargetLoad).and_return(true)
      allow(Y2Packager::MediumType).to receive(:online?).and_return(false)
      stub_subject(subject)
    end

    context "when root partition is mounted" do
      before do
        allow(Yast::RootPart).to receive(:Mounted).and_return(true)
        allow(Yast::RootPart).to receive(:UnmountPartitions)
      end

      it "detachs update" do
        expect(Yast::Update).to receive(:Detach)

        subject.main
      end

      it "unmounts all the root partitions" do
        expect(Yast::RootPart).to receive(:UnmountPartitions).with(false)

        subject.main
      end
    end

    it "obtains the current target system" do
      expect(subject).to receive(:target_system_candidate).once

      subject.main
    end

    context "when a target system can't be obtained" do
      before do
        allow(subject).to receive(:target_system_candidate).and_return(nil)
      end

      it "shows the partition dialog" do
        expect(subject).to receive(:RootPartitionDialog)

        subject.main
      end
    end

    context "when a target system can be obtained" do
      before do
        allow(subject).to receive(:target_system_candidate).and_return("/dev/whatever")
      end

      it "sets the RootPart.selectedRootPartition with its value" do
        expect(Yast::RootPart).to receive(:selectedRootPartition=).with("/dev/whatever")

        subject.main
      end

      it "tries to mount the target" do
        expect(Yast::RootPart).to receive(:mount_target)

        subject.main
      end

      context "when the target system is not mounted" do
        before do
          allow(Yast::RootPart).to receive(:mount_target).and_return(false)
        end

        it "reports and Error" do
          expect(Yast::Report).to receive(:Error).with(_("Failed to mount target system"))

          subject.main
        end

        it "unmount all the partitions" do
          expect(subject).to receive(:UmountMountedPartition).once

          subject.main
        end

        it "shows the partition dialog" do
          expect(subject).to receive(:RootPartitionDialog)

          subject.main
        end
      end

      context "when the target system is mounted successfully" do
        before do
          allow(Yast::RootPart).to receive(:mount_target).and_return(true)
        end

        context "when it detects an incomplete installation" do
          before do
            allow(Yast::RootPart).to receive(:IncompleteInstallationDetected).and_return(true)
          end

          it "reports an error" do
            expect(Yast::Report).to receive(:Error).with("A possibly incomplete installation has been detected.")

            subject.main
          end

          it "unmounts mounted partitions" do
            expect(subject).to receive(:UmountMountedPartition).once

            subject.main
          end

          it "shows the partition dialog" do
            expect(subject).to receive(:RootPartitionDialog)

            subject.main
          end
        end

        context "when Pkg initialization fails in the target" do
          before do
            allow(Yast::Pkg).to receive(:TargetLoad).and_return(false)
          end

          it "reports and error" do
            expect(Yast::Report).to receive(:Error).with("Initializing the target system failed")

            subject.main
          end

          it "unmounts mounted partitions" do
            expect(subject).to receive(:UmountMountedPartition).once

            subject.main
          end

          it "finishes Pkg in the target" do
            expect(Yast::Pkg).to receive(:TargetFinish)

            subject.main
          end
        end

        context "when all checks are fine" do
          before do
            allow(Yast::RootPart).to receive(:IncompleteInstallationDetected).and_return(false)
            allow(Yast::Pkg).to receive(:TargetInitializeOptions).and_return(true)
          end

          it "returns :next without shown selection dialog" do
            expect(subject).not_to receive(:RootPartitionDialog)

            expect(subject.main).to eql(:next)
          end
        end
      end

    end

    context "when a selection in the root partition dialog is done successfully" do
      before do
        allow(subject).to receive(:RootPartitionDialog).and_return(:next)
        allow(subject).to receive(:target_system_candidate).and_return(nil)
      end

      it "returns :next" do
        expect(subject.main).to eql(:next)
      end
    end
  end
end

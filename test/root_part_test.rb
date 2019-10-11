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
end

#!/usr/bin/env rspec

ENV["Y2DIR"] = File.join(File.expand_path(File.dirname(__FILE__)), "../src/")

require "yast"

Yast.import "SUSERelease"

DATA_DIR = File.join(
  File.expand_path(File.dirname(__FILE__)),
  "data"
)

describe Yast::SUSERelease do
  describe "#ReleaseInformation" do
    it "returns product name without any additional information (arch, sub-release)" do
      stub_const("Yast::SUSEReleaseClass::RELEASE_FILE_PATH", "/etc/SuSE-release_0")
      expect(Yast::SUSERelease.ReleaseInformation(DATA_DIR)).to eq "SUSE Linux Enterprise Server 11"

      stub_const("Yast::SUSEReleaseClass::RELEASE_FILE_PATH", "/etc/SuSE-release_1")
      expect(Yast::SUSERelease.ReleaseInformation(DATA_DIR)).to eq "openSUSE 12.2"
    end

    it "raises exception if SuSE-release file is not found" do
      stub_const("Yast::SUSEReleaseClass::RELEASE_FILE_PATH", "/etc/this-file-doesnt-exist")
      expect { Yast::SUSERelease.ReleaseInformation(DATA_DIR) }.to raise_error(
        Yast::SUSEReleaseFileMissingError
      )
    end
  end
end

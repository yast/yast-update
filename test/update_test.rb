#! /usr/bin/rspec

ENV["Y2DIR"] = File.join(File.expand_path(File.dirname(__FILE__)), "../src/")

require "yast"

Yast.import "Update"
Yast.import "Installation"

DATA_DIR = File.join(
  File.expand_path(File.dirname(__FILE__)),
  "data"
)

describe Yast::Update do
  describe "#installed_product" do
    it "returns `nil` if neither os-release nor SuSE-release files exist in Installation.destdir" do
      Yast::Installation.destdir = File.join(DATA_DIR, "update-test-1")
      expect(Yast::Update.installed_product).to be_nil
    end

    it "returns product name from SUSE-release if os-release is missing and SUSE-release exists in Installation.destdir" do
      Yast::Installation.destdir = File.join(DATA_DIR, "update-test-2")
      expect(Yast::Update.installed_product).to eq("SUSE Linux Enterprise Server 11")
    end

    it "returns product name from os-release if such file exists in Installation.destdir" do
      Yast::Installation.destdir = File.join(DATA_DIR, "update-test-3")
      expect(Yast::Update.installed_product).to eq("openSUSE 13.1")
    end
  end
end

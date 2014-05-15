#! /usr/bin/rspec

ENV["Y2DIR"] = File.join(File.expand_path(File.dirname(__FILE__)), "../src/")

require "yast"

Yast.import "Update"
Yast.import "Installation"
Yast.import "ProductControl"
Yast.import "ProductFeatures"
Yast.import "FileUtils"
Yast.import "Misc"
Yast.import "SCR"
Yast.import "Pkg"
Yast.import "Report"

include Yast::Logger

DATA_DIR = File.join(
  File.expand_path(File.dirname(__FILE__)),
  "data"
)

def default_product_control
  Yast::ProductControl.custom_control_file = File.join(DATA_DIR, "control-files", "desktop-upgrade.xml")
  Yast::ProductControl.Init
end

def default_SetDesktopPattern_stubs
  default_product_control
  Yast::Update.stub(:installed_desktop).and_return("sysconfig-desktop")
  Yast::Update.stub(:packages_installed?).and_return(true)
  Yast::Pkg.stub(:ResolvableInstall).with(kind_of(String), :pattern).and_return(true)
  Yast::Pkg.stub(:ResolvableInstall).with(kind_of(String), :package).and_return(true)
end

describe Yast::Update do
  before(:each) do
    log.info "--- test ---"
  end

  describe "#installed_product" do
    it "returns `nil` if neither os-release nor SuSE-release files exist in Installation.destdir" do
      Yast::Installation.stub(:destdir).and_return(File.join(DATA_DIR, "update-test-1"))
      expect(Yast::Update.installed_product).to be_nil
    end

    it "returns product name from SUSE-release if os-release is missing and SUSE-release exists in Installation.destdir" do
      Yast::Installation.stub(:destdir).and_return(File.join(DATA_DIR, "update-test-2"))
      expect(Yast::Update.installed_product).to eq("SUSE Linux Enterprise Server 11")
    end

    it "returns product name from os-release if such file exists in Installation.destdir" do
      Yast::Installation.stub(:destdir).and_return(File.join(DATA_DIR, "update-test-3"))
      expect(Yast::Update.installed_product).to eq("openSUSE 13.1")
    end
  end

  describe "#SetDesktopPattern" do
    context "if there is no definition of window manager upgrade path in control file" do
      it "returns true as there is no upgrade path defined" do
        Yast::ProductFeatures.stub(:GetFeature).with("software","upgrade").and_return(nil)

        expect(Yast::Y2Logger.instance).to receive(:info) do |msg|
          expect(msg).to match(/upgrade is not handled by this product/i)
        end.and_call_original

        expect(Yast::Update.SetDesktopPattern).to be_true
      end
    end

    context "if there is no windowmanager sysconfig file present on the system selected for upgrade" do
      it "returns true as there is nothing to do" do
        default_product_control
        Yast::FileUtils.stub(:Exists).with(/windowmanager/).and_return(false)

        expect(Yast::Y2Logger.instance).to receive(:warn) do |msg|
          expect(msg).to match(/(Sysconfig file .* does not exist|cannot read default window manager)/i)
        end.twice.and_call_original

        expect(Yast::Update.SetDesktopPattern).to be_true
      end
    end

    context "if no upgrade path for the current windowmanager is defined" do
      it "returns true as there is nothing to do" do
        default_product_control
        installed_desktop = "desktop-not-supported-for-upgrade"
        Yast::Update.stub(:installed_desktop).and_return(installed_desktop)

        expect(Yast::Y2Logger.instance).to receive(:info) do |msg|
          expect(msg).to match(/no matching desktop found .* #{installed_desktop}/i)
        end.and_call_original

        expect(Yast::Update.SetDesktopPattern).to be_true
      end
    end

    context "if desktop packages are not installed" do
      it "returns true as there is nothing to upgrade" do
        default_product_control
        Yast::Update.stub(:installed_desktop).and_return("sysconfig-desktop")
        Yast::SCR.stub(:Execute).and_return(0)
        Yast::SCR.stub(:Execute).with(kind_of(Yast::Path), /rpm -q/).and_return(-1)

        expect(Yast::Y2Logger.instance).to receive(:info) do |msg|
          expect(msg).to match(/(package .* installed: false|not all packages .* are installed)/i)
        end.twice.and_call_original

        expect(Yast::Update.SetDesktopPattern).to be_true
      end
    end

    context "all desktop packages are installed" do
      context "and cannot select all patterns for installation" do
        it "returns false" do
          default_SetDesktopPattern_stubs
          Yast::Pkg.stub(:ResolvableInstall).with(kind_of(String), :pattern).and_return(false)

          expect(Yast::Report).to receive(:Error).with(/cannot select these patterns/i)
          expect(Yast::Update.SetDesktopPattern).to be_false
        end
      end

      context "and cannot select all packages for installation" do
        it "returns false" do
          default_SetDesktopPattern_stubs
          Yast::Pkg.stub(:ResolvableInstall).with(kind_of(String), :package).and_return(false)

          expect(Yast::Report).to receive(:Error).with(/cannot select these packages/i)
          expect(Yast::Update.SetDesktopPattern).to be_false
        end
      end

      context "and selecting all resolvables succeeds" do
        it "returns true" do
          default_SetDesktopPattern_stubs

          expect(Yast::Update.SetDesktopPattern).to be_true
        end
      end
    end

  end
end

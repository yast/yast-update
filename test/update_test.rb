#!/usr/bin/env rspec

require_relative "test_helper"

Yast.import "Update"
Yast.import "Installation"
Yast.import "ProductControl"
Yast.import "ProductFeatures"
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

def default_product_control_desktop
  Yast::ProductControl.custom_control_file = File.join(DATA_DIR, "control-files", "desktop-upgrade.xml")
  Yast::ProductControl.Init
end

def default_product_control_system
  Yast::ProductControl.custom_control_file = File.join(DATA_DIR, "control-files", "system-upgrade.xml")
  Yast::ProductControl.Init
end

def default_SetDesktopPattern_stubs
  default_product_control_desktop
  Yast::Update.stub(:installed_desktop).and_return("sysconfig-desktop")
  Yast::Update.stub(:packages_installed?).and_return(true)
  Yast::Pkg.stub(:ResolvableInstall).with(kind_of(String), :pattern).and_return(true)
  Yast::Pkg.stub(:ResolvableInstall).with(kind_of(String), :package).and_return(true)
end

describe Yast::Update do
  before(:each) do
    log.info "--- test ---"
    allow(Yast::Installation).to receive(:destdir).and_return("/mnt")
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

  describe "#create_backup" do
    before(:each) do
      allow(::FileUtils).to receive(:mkdir_p)
      allow(::File).to receive(:write)
      allow(::FileUtils).to receive(:chmod)
      allow(::File).to receive(:exist?).and_return(true)
      allow(Yast::SCR).to receive(:Execute).with(Yast::Path.new(".target.bash_output"), /^tar /).
        and_return({"exit" => 0})
    end

    it "create tarball including given name with all paths added" do
      name = "test-backup"
      paths = ["a", "b"]
      expect(Yast::SCR).to receive(:Execute).with(Yast::Path.new(".target.bash_output"), /^tar c.*a.*b.*#{name}.tar.gz/).
        and_return({"exit" => 0})
      Yast::Update.create_backup(name, paths)
    end

    it "strips leading '/' from paths" do
      name = "test-backup"
      paths = ["/path_with_slash", "path_without_slash"]
      expect(Yast::SCR).to receive(:Execute).with(Yast::Path.new(".target.bash_output"), / path_with_slash/).
        and_return({"exit" => 0})
      Yast::Update.create_backup(name, paths)
    end

    it "do not store mount prefix in tarball" do
      name = "test-backup"
      paths = ["/path_with_slash"]
      expect(Yast::SCR).to receive(:Execute).with(Yast::Path.new(".target.bash_output"), /-C '\/mnt'/).
        and_return({"exit" => 0})
      Yast::Update.create_backup(name, paths)
    end

    it "change permission of tarball to be readable only for creator" do
      name = "test-backup"
      paths = ["a", "b"]
      expect(::FileUtils).to receive(:chmod).with(0600, /test-backup\.tar.gz/)

      Yast::Update.create_backup(name, paths)
    end

    it "raise exception if creating tarball failed" do
      name = "test-backup"
      paths = ["/path_with_slash"]
      expect(Yast::SCR).to receive(:Execute).with(Yast::Path.new(".target.bash_output"), /tar/).
        and_return({"exit" => 1})
      expect{Yast::Update.create_backup(name, paths)}.to raise_error
    end

    it "create restore script" do
      name = "test-backup"
      paths = ["a", "b"]
      expect(File).to receive(:write)

      Yast::Update.create_backup(name, paths)
    end

    it "set executable permission on restore script" do
      name = "test-backup"
      paths = ["a", "b"]

      expect(::FileUtils).to receive(:chmod).with(0744, /restore-test-backup\.sh/)

      Yast::Update.create_backup(name, paths)
    end
  end

  describe "#clean_backup" do
    it "removes backup directory with its content" do
      expect(::FileUtils).to receive(:rm_r).with(/\/mnt.*system-upgrade.*/, anything())

      Yast::Update.clean_backup
    end
  end

  describe "#restore_backup" do
    it "call all restore scripts in backup directory" do
      expect(::Dir).to receive(:glob).and_return(["restore-a.sh", "restore-b.sh"])
      expect(Yast::SCR).to receive(:Execute).with(Yast::Path.new(".target.bash_output"), /sh .*restore-a.sh \/mnt/).
        and_return({"exit" => 0})
      expect(Yast::SCR).to receive(:Execute).with(Yast::Path.new(".target.bash_output"), /sh .*restore-b.sh \/mnt/).
        and_return({"exit" => 0})

      Yast::Update.restore_backup
    end
  end


  describe "#SetDesktopPattern" do
    context "if there is no definition of window manager upgrade path in control file" do
      it "returns true as there is no upgrade path defined" do
        Yast::ProductFeatures.stub(:GetFeature).with("software","upgrade").and_return(nil)

        expect(Yast::Y2Logger.instance).to receive(:info) do |msg|
          expect(msg).to match(/upgrade is not handled by this product/i)
        end.and_call_original

        expect(Yast::Update.SetDesktopPattern).to eq(true)
      end
    end

    context "if there is no windowmanager sysconfig file present on the system selected for upgrade" do
      it "returns true as there is nothing to do" do
        default_product_control_desktop
        Yast::FileUtils.stub(:Exists).with(/windowmanager/).and_return(false)

        expect(Yast::Y2Logger.instance).to receive(:warn) do |msg|
          expect(msg).to match(/(Sysconfig file .* does not exist|cannot read default window manager)/i)
        end.twice.and_call_original

        expect(Yast::Update.SetDesktopPattern).to eq(true)
      end
    end

    context "if no upgrade path for the current windowmanager is defined" do
      it "returns true as there is nothing to do" do
        default_product_control_desktop
        installed_desktop = "desktop-not-supported-for-upgrade"
        Yast::Update.stub(:installed_desktop).and_return(installed_desktop)

        expect(Yast::Y2Logger.instance).to receive(:info) do |msg|
          expect(msg).to match(/no matching desktop found .* #{installed_desktop}/i)
        end.and_call_original

        expect(Yast::Update.SetDesktopPattern).to eq(true)
      end
    end

    context "if desktop packages are not installed" do
      it "returns true as there is nothing to upgrade" do
        default_product_control_desktop
        Yast::Update.stub(:installed_desktop).and_return("sysconfig-desktop")
        Yast::SCR.stub(:Execute).and_return(0)
        Yast::SCR.stub(:Execute).with(kind_of(Yast::Path), /rpm -q/).and_return(-1)

        expect(Yast::Y2Logger.instance).to receive(:info) do |msg|
          expect(msg).to match(/(package .* installed: false|not all packages .* are installed)/i)
        end.twice.and_call_original

        expect(Yast::Update.SetDesktopPattern).to eq(true)
      end
    end

    context "all desktop packages are installed" do
      context "and cannot select all patterns for installation" do
        it "returns false" do
          default_SetDesktopPattern_stubs
          Yast::Pkg.stub(:ResolvableInstall).with(kind_of(String), :pattern).and_return(false)

          expect(Yast::Report).to receive(:Error).with(/cannot select these patterns/i)
          expect(Yast::Update.SetDesktopPattern).to eq(false)
        end
      end

      context "and cannot select all packages for installation" do
        it "returns false" do
          default_SetDesktopPattern_stubs
          Yast::Pkg.stub(:ResolvableInstall).with(kind_of(String), :package).and_return(false)

          expect(Yast::Report).to receive(:Error).with(/cannot select these packages/i)
          expect(Yast::Update.SetDesktopPattern).to eq(false)
        end
      end

      context "and selecting all resolvables succeeds" do
        it "returns true" do
          default_SetDesktopPattern_stubs

          expect(Yast::Update.SetDesktopPattern).to eq(true)
        end
      end
    end
  end

  describe "#IsProductSupportedForUpgrade" do
    it "returns whether upgrade of the installed system to the new product is supported" do
      # uses stored product control file, test for bnc#947398
      default_product_control_system

      # Supported systems
      allow(Yast::Update).to receive(:installed_product).and_return("openSUSE Leap 42.1 Milestone 2")
      expect(Yast::Update.IsProductSupportedForUpgrade).to be(true)

      allow(Yast::Update).to receive(:installed_product).and_return("openSUSE 13.1")
      expect(Yast::Update.IsProductSupportedForUpgrade).to be(true)

      allow(Yast::Update).to receive(:installed_product).and_return("openSUSE 12.2")
      expect(Yast::Update.IsProductSupportedForUpgrade).to be(true)

      # Unsupported systems
      allow(Yast::Update).to receive(:installed_product).and_return("openSUSE 11.2")
      expect(Yast::Update.IsProductSupportedForUpgrade).to be(false)

      allow(Yast::Update).to receive(:installed_product).and_return("Some Other Linux 8.4")
      expect(Yast::Update.IsProductSupportedForUpgrade).to be(false)
    end
  end
end

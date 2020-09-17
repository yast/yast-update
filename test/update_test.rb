#!/usr/bin/env rspec

require_relative "test_helper"

Yast.import "Update"
Yast.import "Installation"
Yast.import "ProductControl"
Yast.import "ProductFeatures"
Yast.import "FileUtils"
Yast.import "Misc"
Yast.import "SCR"
Yast.import "Pkg"
Yast.import "Report"

DATA_DIR = File.join(
  __dir__,
  "data"
)

def default_product_control_desktop
  Yast::ProductControl.custom_control_file = File.join(DATA_DIR, "control-files",
    "desktop-upgrade.xml")
  Yast::ProductControl.Init
end

def default_product_control_system
  Yast::ProductControl.custom_control_file = File.join(DATA_DIR, "control-files",
    "system-upgrade.xml")
  Yast::ProductControl.Init
end

def default_SetDesktopPattern_stubs
  default_product_control_desktop
  allow(Yast::Update).to receive(:installed_desktop).and_return("sysconfig-desktop")
  allow(Yast::Update).to receive(:packages_installed?).and_return(true)
  allow(Yast::Pkg).to receive(:ResolvableInstall).with(kind_of(String), :pattern).and_return(true)
  allow(Yast::Pkg).to receive(:ResolvableInstall).with(kind_of(String), :package).and_return(true)
end

describe Yast::Update do
  include Yast::Logger

  before(:each) do
    log.info "--- test ---"
    allow(Yast::Installation).to receive(:destdir).and_return("/mnt")
  end

  describe "#installed_product" do
    it "returns `nil` if neither os-release nor SuSE-release files exist in Installation.destdir" do
      allow(Yast::Installation).to receive(:destdir)
        .and_return(File.join(DATA_DIR, "update-test-1"))
      expect(Yast::Update.installed_product).to be_nil
    end

    it "returns product name from SUSE-release if os-release is missing and " \
        "SUSE-release exists in Installation.destdir" do
      allow(Yast::Installation).to receive(:destdir)
        .and_return(File.join(DATA_DIR, "update-test-2"))
      expect(Yast::Update.installed_product).to eq("SUSE Linux Enterprise Server 11")
    end

    it "returns product name from os-release if such file exists in Installation.destdir" do
      allow(Yast::Installation).to receive(:destdir)
        .and_return(File.join(DATA_DIR, "update-test-3"))
      expect(Yast::Update.installed_product).to eq("openSUSE 13.1")
    end
  end

  describe "#create_backup" do
    before(:each) do
      allow(::FileUtils).to receive(:cp)
      allow(::FileUtils).to receive(:mkdir_p)
      allow(::File).to receive(:write)
      allow(::FileUtils).to receive(:chmod)
      allow(::File).to receive(:exist?).and_return(true)
      allow(Pathname).to receive(:new).and_return(double("Pathname", exist?: true))
      allow(Yast::SCR).to receive(:Execute).with(Yast::Path.new(".target.bash_output"), /^tar /)
        .and_return("exit" => 0)
    end

    let(:backup_dir) { "#{Yast::Installation.destdir}/#{Yast::UpdateClass::BACKUP_DIR}" }
    let(:backup_dir_pathname) { double("Pathname") }
    let(:os_release_pathname) { double }

    context "when backup directory does not exit yet" do
      before do
        allow(Pathname).to receive(:new).with(backup_dir).and_return(backup_dir_pathname)
        allow(backup_dir_pathname).to receive(:exist?).and_return(false)
      end

      it "creates it" do
        expect(::FileUtils).to receive(:mkdir_p).with(backup_dir_pathname)

        Yast::Update.create_backup("test", [])
      end
    end

    context "when backup directory is alreday present" do
      before do
        allow(Pathname).to receive(:new).with(backup_dir).and_return(backup_dir_pathname)
        allow(backup_dir_pathname).to receive(:exist?).and_return(true)
      end

      it "does not create it again" do
        expect(::FileUtils).to_not receive(:mkdir_p).with(backup_dir_pathname)

        Yast::Update.create_backup("test", [])
      end
    end

    it "copies the release info file" do
      allow(Pathname).to receive(:new)
        .with("#{Yast::Installation.destdir}/etc/os-release")
        .and_return(os_release_pathname)

      expect(::FileUtils).to receive(:cp).with(os_release_pathname, anything)

      Yast::Update.create_backup("testing", [])
    end

    it "does not crash when os-release file does not exists" do
      allow(::FileUtils).to receive(:cp).and_raise(Errno::ENOENT)

      expect { Yast::Update.create_backup("testing", []) }.to_not raise_error
    end

    it "create tarball including given name with all paths added" do
      name = "test-backup"
      paths = ["a", "b"]
      expect(Yast::SCR).to receive(:Execute)
        .with(Yast::Path.new(".target.bash_output"), /^tar c.*a.*b.*#{name}.tar.gz/)
        .and_return("exit" => 0)
      Yast::Update.create_backup(name, paths)
    end

    it "strips leading '/' from paths" do
      name = "test-backup"
      paths = ["/path_with_slash", "path_without_slash"]
      expect(Yast::SCR).to receive(:Execute)
        .with(Yast::Path.new(".target.bash_output"), / path_with_slash/)
        .and_return("exit" => 0)
      Yast::Update.create_backup(name, paths)
    end

    it "do not store mount prefix in tarball" do
      name = "test-backup"
      paths = ["/path_with_slash"]
      expect(Yast::SCR).to receive(:Execute)
        .with(Yast::Path.new(".target.bash_output"), /-C '\/mnt'/)
        .and_return("exit" => 0)
      Yast::Update.create_backup(name, paths)
    end

    it "change permission of tarball to be readable only for creator" do
      name = "test-backup"
      paths = ["a", "b"]
      expect(::FileUtils).to receive(:chmod).with(0o600, /test-backup\.tar.gz/)

      Yast::Update.create_backup(name, paths)
    end

    it "raise exception if creating tarball failed" do
      name = "test-backup"
      paths = ["/path_with_slash"]
      expect(Yast::SCR).to receive(:Execute).with(Yast::Path.new(".target.bash_output"), /tar/)
        .and_return("exit" => 1)
      expect { Yast::Update.create_backup(name, paths) }.to(
        raise_error(RuntimeError, "Failed to create backup")
      )
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

      expect(::FileUtils).to receive(:chmod).with(0o744, /restore-test-backup\.sh/)

      Yast::Update.create_backup(name, paths)
    end
  end

  describe "#clean_backup" do
    it "removes backup directory with its content" do
      expect(::FileUtils).to receive(:rm_r).with(/\/mnt.*system-upgrade.*/, anything)

      Yast::Update.clean_backup
    end
  end

  describe "#restore_backup" do
    let(:os_release_pathname) { double }
    let(:os_backup_release_pathname) { double }
    let(:os_release_content) { File.new("#{DATA_DIR}/etc/leap-15-os-release").read }
    let(:os_backup_release_content) { File.new("#{DATA_DIR}/etc/tw-os-release").read }
    let(:backup_dir) { "#{Yast::Installation.destdir}/#{Yast::UpdateClass::BACKUP_DIR}" }

    before do
      allow(Yast::Update.log).to receive(:info).and_call_original

      allow(::Dir).to receive(:glob).and_return(["restore-a.sh", "restore-b.sh"])

      allow(Pathname).to receive(:new)
        .with("#{Yast::Installation.destdir}/etc/os-release")
        .and_return(os_release_pathname)
      allow(Pathname).to receive(:new)
        .with("#{backup_dir}/os-release")
        .and_return(os_backup_release_pathname)
      allow(os_release_pathname).to receive(:read).and_return(os_release_content)
      allow(os_backup_release_pathname).to receive(:read).and_return(os_backup_release_content)
    end

    it "check the release info files" do
      expect(Pathname).to receive(:new)
        .with("#{Yast::Installation.destdir}/etc/os-release")
      expect(Pathname).to receive(:new)
        .with("#{backup_dir}/os-release")

      Yast::Update.restore_backup
    end

    context "when any file does not exists" do
      it "does not crash" do
        allow(os_backup_release_pathname).to receive(:read).and_raise(Errno::ENOENT)

        expect { Yast::Update.restore_backup }.to_not raise_error
      end
    end

    context "when the release info match" do
      let(:os_backup_release_content) { os_release_content }

      it "call all restore scripts in backup directory" do
        expect(Yast::SCR).to receive(:Execute)
          .with(Yast::Path.new(".target.bash_output"), /sh .*restore-a.sh \/mnt/)
        expect(Yast::SCR).to receive(:Execute)
          .with(Yast::Path.new(".target.bash_output"), /sh .*restore-b.sh \/mnt/)

        Yast::Update.restore_backup
      end
    end

    context "when the release info does not match" do
      it "logs info and error" do
        expect(Yast::Update.log).to receive(:info)
          .with("Version expected: opensuse-leap-15.0. " \
            "Backup version: opensuse-tumbleweed-20180911")
          .and_call_original
        expect(Yast::Update.log).to receive(:error).with(/not restored/).and_call_original

        Yast::Update.restore_backup
      end

      it "does not continue" do
        expect(Yast::SCR).to_not receive(:Execute)
          .with(Yast::Path.new(".target.bash_output"), /sh .*restore-a.sh \/mnt/)
        expect(Yast::SCR).to_not receive(:Execute)
          .with(Yast::Path.new(".target.bash_output"), /sh .*restore-b.sh \/mnt/)

        Yast::Update.restore_backup
      end
    end
  end

  describe "#SetDesktopPattern" do
    context "if there is no definition of window manager upgrade path in control file" do
      it "returns true as there is no upgrade path defined" do
        allow(Yast::ProductFeatures).to receive(:GetFeature).with("software", "upgrade")
          .and_return(nil)

        expect(Yast::Y2Logger.instance).to receive(:info)\
          .with(/upgrade is not handled by this product/i)\
          .and_call_original

        expect(Yast::Update.SetDesktopPattern).to eq(true)
      end
    end

    context "if there is no windowmanager sysconfig file present " \
        "on the system selected for upgrade" do
      it "returns true as there is nothing to do" do
        default_product_control_desktop
        allow(Yast::FileUtils).to receive(:Exists).with(/windowmanager/).and_return(false)

        expect(Yast::Y2Logger.instance).to receive(:warn)\
          .with(/(Sysconfig file .* does not exist|cannot read default window manager)/i)\
          .twice.and_call_original

        expect(Yast::Update.SetDesktopPattern).to eq(true)
      end
    end

    context "if no upgrade path for the current windowmanager is defined" do
      it "returns true as there is nothing to do" do
        default_product_control_desktop
        installed_desktop = "desktop-not-supported-for-upgrade"
        allow(Yast::Update).to receive(:installed_desktop).and_return(installed_desktop)

        expect(Yast::Y2Logger.instance).to receive(:info)\
          .with(/no matching desktop found .* #{installed_desktop}/i)\
          .and_call_original

        expect(Yast::Update.SetDesktopPattern).to eq(true)
      end
    end

    context "if desktop packages are not installed" do
      it "returns true as there is nothing to upgrade" do
        default_product_control_desktop
        allow(Yast::Update).to receive(:installed_desktop).and_return("sysconfig-desktop")
        allow(Yast::SCR).to receive(:Execute).and_return(0)
        allow(Yast::SCR).to receive(:Execute).with(kind_of(Yast::Path), /rpm -q/)
          .and_return(-1)

        expect(Yast::Y2Logger.instance).to receive(:info)\
          .with(/(package .* installed: false|not all packages .* are installed)/i)\
          .twice.and_call_original

        expect(Yast::Update.SetDesktopPattern).to eq(true)
      end
    end

    context "all desktop packages are installed" do
      context "and cannot select all patterns for installation" do
        it "returns false" do
          default_SetDesktopPattern_stubs
          allow(Yast::Pkg).to receive(:ResolvableInstall).with(kind_of(String), :pattern)
            .and_return(false)

          expect(Yast::Report).to receive(:Error).with(/cannot select these patterns/i)
          expect(Yast::Update.SetDesktopPattern).to eq(false)
        end
      end

      context "and cannot select all packages for installation" do
        it "returns false" do
          default_SetDesktopPattern_stubs
          allow(Yast::Pkg).to receive(:ResolvableInstall).with(kind_of(String), :package)
            .and_return(false)

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
      allow(Yast::Update).to receive(:installed_product)
        .and_return("openSUSE Leap 42.1 Milestone 2")
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

  describe "#InitUpdate" do
    context "no compatile vendors are defined in the control file" do
      before do
        allow(Yast::ProductFeatures).to receive(:GetFeature)
          .with("software", "compatible_vendors")
          .and_return(nil)
        allow(Yast::ProductFeatures).to receive(:GetFeature)
          .with("software", "silently_downgrade_packages")
          .and_return(true)
      end

      it "does nothing" do
        expect(Yast::Pkg).to_not receive(:SetAdditionalVendors)
        Yast::Update.InitUpdate()
      end
    end

    context "compatilbe vendors are defined in the control file" do
      before do
        allow(Yast::ProductFeatures).to receive(:GetFeature)
          .with("software", "compatible_vendors")
          .and_return(["openSUSE", "SLES"])
        allow(Yast::ProductFeatures).to receive(:GetFeature)
          .with("software", "silently_downgrade_packages")
          .and_return(true)
      end

      it "set it in the solver" do
        expect(Yast::Pkg).to receive(:SetAdditionalVendors).with(kind_of(Array))
        Yast::Update.InitUpdate()
      end
    end
  end

end

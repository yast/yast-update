ENV["Y2DIR"] = File.join(File.expand_path(File.dirname(__FILE__)), "../src/")

require "yast"
require "yast/rspec"

def stub_root_part
  allow(Yast::RootPart).to receive(:Mounted)
  allow(Yast::RootPart).to receive(:UnmountPartitions)
  allow(Yast::RootPart).to receive(:mount_target)
  allow(Yast::RootPart).to receive(:IncompleteInstallationDetected)
end

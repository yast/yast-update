ENV["Y2DIR"] = File.join(File.expand_path(File.dirname(__FILE__)), "../src/")

require "yast"
require "yast/rspec"

def stub_root_part
  allow(Yast::RootPart).to receive(:Detect)
  allow(Yast::RootPart).to receive(:Mounted)
  allow(Yast::RootPart).to receive(:UnmountPartitions)
  allow(Yast::RootPart).to receive(:mount_target)
  allow(Yast::RootPart).to receive(:IncompleteInstallationDetected)
end

def stub_subject(subject)
  allow(subject).to receive(:current_target_system).and_return(nil)
  allow(subject).to receive(:RootPartitionDialog).and_return(:cancel)
  allow(subject).to receive(:UmountMountedPartition)
  allow(subject).to receive(:target_distribution).and_return("sle-12-x86_64")
  allow(subject).to receive(:initialize_update_rootpart)
  allow(subject).to receive(:load_data)
  allow(subject).to receive(:store_data)
end

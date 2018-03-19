module Helpers
  def stub_root_part
    allow(Yast::RootPart).to receive(:Detect)
    allow(Yast::RootPart).to receive(:Mounted)
    allow(Yast::RootPart).to receive(:UnmountPartitions)
    allow(Yast::RootPart).to receive(:rootPartitions).and_return({})
    allow(Yast::RootPart).to receive(:mount_target)
    allow(Yast::RootPart).to receive(:IncompleteInstallationDetected)
  end

  def stub_subject(subject)
    allow(subject).to receive(:target_system_candidate).and_return(nil)
    allow(subject).to receive(:RootPartitionDialog).and_return(:cancel)
    allow(subject).to receive(:UmountMountedPartition)
    allow(subject).to receive(:target_distribution).and_return("sle-12-x86_64")
    allow(subject).to receive(:initialize_update_rootpart)
    allow(subject).to receive(:load_data)
  end

  def stub_storage(devicegraph_file)
    path = File.join(File.dirname(__FILE__), "data", "devicegraphs", devicegraph_file)
    if path.end_with?(".xml")
      Y2Storage::StorageManager.create_test_instance.probe_from_xml(path)
    else
      Y2Storage::StorageManager.create_test_instance.probe_from_yaml(path)
    end
  end
end

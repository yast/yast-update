#!/usr/bin/env rspec

require_relative "test_helper"
require_relative "../src/clients/packages_proposal"

describe Yast::PackagesProposalClient do
  subject(:client) { described_class.new }

  before do
    allow(Yast::WFM).to receive(:Args) do |n|
      n.nil? ? args : args[n]
    end
  end

  describe "#main" do
    context "when action is MakeProposal" do
      let(:args) { ["MakeProposal"] }

      PACKAGES = {
        installed: ["grub", "elilo"],
        selected:  ["grub", "grub2-efi", "grub2-pc"],
        removed:   ["elilo"]
      }.freeze

      before do
        allow(Yast::SpaceCalculation).to receive(:GetPartitionWarning)
          .and_return(nil)
        allow(Yast::Packages).to receive(:proposal_for_update)
        allow(Yast::Pkg).to receive(:GetPackages).with(anything, true) do |status, _names_only|
          PACKAGES[status]
        end
      end

      it "asks for a packages selection proposal" do
        expect(Yast::Packages).to receive(:proposal_for_update)
        client.main
      end

      it "summarizes packages to update/install/remove" do
        expect(Yast::Update).to receive(:packages_to_update=)
          .with(1)
        expect(Yast::Update).to receive(:packages_to_install=)
          .with(2)
        expect(Yast::Update).to receive(:packages_to_remove=)
          .with(1)
        client.main
      end

      it "is meant to be triggered if packages proposal changes" do
        expect(client.main["trigger"]).to eq(
          "expect" => { "class" => "Yast::Packages", "method" => "PackagesProposalChanged" },
          "value"  => false
        )
      end
    end
  end
end

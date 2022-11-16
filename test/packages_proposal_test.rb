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
          .and_return([])
        allow(Yast::Packages).to receive(:proposal_for_update)
        allow(Yast::Pkg).to receive(:GetPackages).with(anything, true) do |status, _names_only|
          PACKAGES[status]
        end
        allow(Y2Packager::Resolvable).to receive(:find).and_return([])
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

      it "returns a warning with removed 3rd party orphaned packages" do
        orphaned = Y2Packager::Resolvable.new(
          arch:     "x86_64",
          kind:     :package,
          name:     "orphaned",
          path:     "",
          source:   -1,
          status:   :removed,
          vendor:   "Foo Corporation",
          version:  "42.0.0",
          orphaned: true
        )

        expect(Y2Packager::Resolvable).to receive(:find).with(
          { kind: :package, status: :removed, orphaned: true },
          [:vendor]
        ).and_return([orphaned])

        result = client.main

        expect(result["warning"]).to include("orphaned-42.0.0.x86_64 (Foo Corporation)")
        expect(result["warning_level"]).to eq(:warning)
      end
    end
  end
end

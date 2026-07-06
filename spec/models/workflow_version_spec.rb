require 'rails_helper'

RSpec.describe WorkflowVersion, type: :model do
  context ".latest_version_of" do
    it "returns the highest version for a workflow by descending order" do
      create(:workflow_version, workflow: "short-read-mngs", version: "8.2.3")
      create(:workflow_version, workflow: "short-read-mngs", version: "8.2.4")
      create(:workflow_version, workflow: "short-read-mngs", version: "8.2.10")
      # Note: ordering is lexical (ORDER version DESC), which the model documents.
      # "8.2.4" sorts after "8.2.10" and "8.2.3" lexically.
      expect(WorkflowVersion.latest_version_of("short-read-mngs")).to eq("8.2.4")
    end

    it "scopes to the requested workflow only" do
      create(:workflow_version, workflow: "consensus-genome", version: "3.0.0")
      create(:workflow_version, workflow: "short-read-mngs", version: "1.0.0")
      expect(WorkflowVersion.latest_version_of("consensus-genome")).to eq("3.0.0")
    end

    it "raises when no versions exist for the workflow" do
      expect do
        WorkflowVersion.latest_version_of("does-not-exist")
      end.to raise_error(/No WorkflowVersions for workflow=does-not-exist exist/)
    end
  end

  context "attributes" do
    it "persists deprecated and runnable flags" do
      wv = create(:workflow_version, workflow: "amr", version: "1.2.3", deprecated: true, runnable: false)
      expect(wv.reload.deprecated).to be(true)
      expect(wv.runnable).to be(false)
    end
  end
end

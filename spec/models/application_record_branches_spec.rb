# frozen_string_literal: true

require "rails_helper"

# Coverage Wave 3: branch sweep for ApplicationRecord#log_analytics. The main
# spec only covers safe_order_dir / mysql_nulls; log_analytics' property-builder
# ternaries (id/name/*_id respond_to? branches) and the ENABLE_MODEL_AUTO_
# ANALYTICS short-circuit are untaken. Annotation opts in, so creating one
# drives the truthy arms; a plain non-flagged model drives the short-circuit.
RSpec.describe ApplicationRecord, type: :model do
  describe "#log_analytics" do
    it "short-circuits for a model not flagged for auto-analytics (the unless guard)" do
      # MetadataField does not set ENABLE_MODEL_AUTO_ANALYTICS and creates no
      # flagged associations, so no event should fire.
      expect(MetricUtil).not_to receive(:log_analytics_event)
      create(:metadata_field)
    end

    it "fires an analytics event with resolved properties for a flagged model (the respond_to? truthy arms)" do
      project = create(:project)
      pipeline_run = create(:pipeline_run, sample: create(:sample, project: project))

      captured = nil
      allow(MetricUtil).to receive(:log_analytics_event) do |event, _user, properties, _request|
        captured = [event, properties]
      end

      annotation = Annotation.create!(pipeline_run_id: pipeline_run.id, tax_id: 573, content: :hit)

      expect(captured).not_to be_nil
      event, properties = captured
      expect(event).to eq("annotation_created")
      # id resolved (line 81 truthy), pipeline_run_id resolved (line 89 truthy),
      # nil-valued keys stripped (delete_if), status keys merged.
      expect(properties[:id]).to eq(annotation.id)
      expect(properties[:pipeline_run_id]).to eq(pipeline_run.id)
      # Annotation has no name/user_id/project_id/sample_id -> stripped as nil.
      expect(properties).not_to have_key(:name)
      expect(properties).not_to have_key(:user_id)
    end

    it "omits the name property for User records (PII guard, line 84 else)" do
      captured_props = nil
      allow(MetricUtil).to receive(:log_analytics_event) do |_event, _user, properties, _request|
        captured_props = properties
      end

      # User opts into auto-analytics; the name ternary's class == User.name arm
      # forces name to nil so it is stripped.
      create(:user, name: "Secret Person")

      expect(captured_props).not_to be_nil
      expect(captured_props).not_to have_key(:name)
    end
  end
end

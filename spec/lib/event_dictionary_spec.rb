# frozen_string_literal: true

require "rails_helper"

# EventDictionary is a registry of analytics event-name constants. The value that
# matters is that each constant equals its own name (SQL-friendly, self-describing)
# and that there are no accidental duplicate string values across constants.
RSpec.describe EventDictionary do
  # Every String constant defined directly on the class.
  def string_constants
    described_class.constants.each_with_object({}) do |const_name, acc|
      value = described_class.const_get(const_name)
      acc[const_name] = value if value.is_a?(String)
    end
  end

  it "defines each event constant as a String equal to its own constant name" do
    string_constants.each do |const_name, value|
      expect(value).to eq(const_name.to_s),
                       "expected #{const_name} to equal \"#{const_name}\", got \"#{value}\""
    end
  end

  it "freezes every event-name string" do
    string_constants.each_value do |value|
      expect(value).to be_frozen
    end
  end

  it "has no duplicate event-name values" do
    values = string_constants.values
    expect(values.uniq.length).to eq(values.length)
  end

  it "exposes the known analytics events" do
    expect(described_class::PIPELINE_RUN_SUCCEEDED).to eq("PIPELINE_RUN_SUCCEEDED")
    expect(described_class::SAMPLE_UPLOAD_STARTED).to eq("SAMPLE_UPLOAD_STARTED")
    expect(described_class::GDPR_RUN_HARD_DELETED).to eq("GDPR_RUN_HARD_DELETED")
  end
end

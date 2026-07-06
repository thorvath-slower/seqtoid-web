require "rails_helper"

RSpec.describe ErrorHelper, type: :helper do
  describe "ErrorHelper::VersionControlErrors" do
    it "formats workflow_version_not_found" do
      msg = ErrorHelper::VersionControlErrors.workflow_version_not_found("consensus-genome", "3.4")
      expect(msg).to eq("WorkflowVersion for workflow=consensus-genome and version_prefix=3.4 does not exist")
    end

    it "formats workflow_name_not_found" do
      msg = ErrorHelper::VersionControlErrors.workflow_name_not_found("amr")
      expect(msg).to eq("No WorkflowVersions for workflow=amr exist.")
    end

    it "formats workflow_version_deprecated" do
      msg = ErrorHelper::VersionControlErrors.workflow_version_deprecated("amr", "1.0.0")
      expect(msg).to eq("WorkflowVersion for workflow=amr and version=1.0.0 is deprecated")
    end

    it "formats workflow_version_not_runnable" do
      msg = ErrorHelper::VersionControlErrors.workflow_version_not_runnable("amr", "1.0.0")
      expect(msg).to eq("WorkflowVersion for workflow=amr and version=1.0.0 is not runnable")
    end

    it "formats project_workflow_version_already_pinned" do
      msg = ErrorHelper::VersionControlErrors.project_workflow_version_already_pinned(42, "amr", "1.0.0")
      expect(msg).to include("Project 42 is already pinned")
      expect(msg).to include("workflow=amr")
      expect(msg).to include("version 1.0.0")
    end
  end

  describe "ErrorHelper::ThresholdFilterErrors" do
    it "formats invalid_count_type" do
      msg = ErrorHelper::ThresholdFilterErrors.invalid_count_type("BAD")
      expect(msg).to include("Invalid count_type provided: BAD")
    end

    it "formats invalid_operator" do
      msg = ErrorHelper::ThresholdFilterErrors.invalid_operator("~~")
      expect(msg).to include("Invalid operator provided: ~~")
    end

    it "formats invalid_metric" do
      msg = ErrorHelper::ThresholdFilterErrors.invalid_metric("nope")
      expect(msg).to include("Invalid metric provided: nope")
    end

    it "formats invalid_tax_level" do
      msg = ErrorHelper::ThresholdFilterErrors.invalid_tax_level("99")
      expect(msg).to include("Invalid tax level provided: 99")
    end
  end

  describe "ErrorHelper::MetadataUploadErrors" do
    it "formats invalid_sample_name" do
      expect(ErrorHelper::MetadataUploadErrors.invalid_sample_name("foo"))
        .to eq("'foo' does not match any samples in this project")
    end

    it "formats save_error" do
      expect(ErrorHelper::MetadataUploadErrors.save_error("host_age", "abc"))
        .to eq("Could not save 'host_age', 'abc'")
    end
  end

  describe "ErrorHelper::FrontendMetricErrors" do
    it "formats invalid_route" do
      expect(ErrorHelper::FrontendMetricErrors.invalid_route("/foo", "GET"))
        .to eq("No route matches '/foo' with http method 'GET'")
    end
  end

  describe "ErrorHelper::SampleUploadErrors" do
    it "formats exceeded_sample_upload_limit" do
      msg = ErrorHelper::SampleUploadErrors.exceeded_sample_upload_limit(500, 100, "cli")
      expect(msg).to include("client=cli")
      expect(msg).to include("upload 500 samples")
      expect(msg).to include("maximum is 100")
    end

    it "formats invalid_project_id" do
      expect(ErrorHelper::SampleUploadErrors.invalid_project_id({ "name" => "s1" }))
        .to eq("Could not save sample 's1'. Invalid project id.")
    end

    it "formats missing_required_technology_for_cg" do
      expect(ErrorHelper::SampleUploadErrors.missing_required_technology_for_cg(9))
        .to include("in project 9. Missing required technology")
    end

    it "formats missing_required_metadata" do
      msg = ErrorHelper::SampleUploadErrors.missing_required_metadata({ "name" => "s1" }, %w[collection_date sample_type])
      expect(msg).to eq("Could not save sample 's1'. Missing required metadata: collection_date, sample_type")
    end

    it "formats missing_input_files_or_basespace_params" do
      expect(ErrorHelper::SampleUploadErrors.missing_input_files_or_basespace_params("s1"))
        .to include("Could not save sample 's1'.")
    end

    it "formats error_fetching_basespace_files_for_dataset" do
      expect(ErrorHelper::SampleUploadErrors.error_fetching_basespace_files_for_dataset("ds1", "s1", 7))
        .to eq("Error fetching Basespace files for dataset ds1 for sample 's1' (7)")
    end

    it "formats no_files_in_basespace_dataset" do
      expect(ErrorHelper::SampleUploadErrors.no_files_in_basespace_dataset("ds1", "s1", 7))
        .to include("No files were found")
    end

    it "formats upload_from_basespace_failed" do
      expect(ErrorHelper::SampleUploadErrors.upload_from_basespace_failed("s1", 7, "f.fastq", "ds1", 3))
        .to include("failed after 3 retries")
    end

    it "formats max_file_size_exceeded" do
      expect(ErrorHelper::SampleUploadErrors.max_file_size_exceeded(200, 100))
        .to eq("File size of 200 exceeds maximum of 100 bytes")
    end
  end

  describe "#get_field_error" do
    let(:field) { MetadataField.new(base_type: base_type) }

    context "for a LOCATION_TYPE field" do
      let(:base_type) { MetadataField::LOCATION_TYPE }

      it "returns the human variant when is_human" do
        expect(helper.get_field_error(field, true)).to eq(ErrorHelper::LOCATION_INVALID_ERROR_HUMAN)
      end

      it "returns the non-human variant otherwise" do
        expect(helper.get_field_error(field, false)).to eq(ErrorHelper::LOCATION_INVALID_ERROR)
      end
    end

    context "for a DATE_TYPE field" do
      let(:base_type) { MetadataField::DATE_TYPE }

      it "returns the human variant when is_human" do
        expect(helper.get_field_error(field, true)).to eq(ErrorHelper::DATE_INVALID_ERROR_HUMAN)
      end

      it "returns the non-human variant otherwise" do
        expect(helper.get_field_error(field)).to eq(ErrorHelper::DATE_INVALID_ERROR)
      end
    end

    context "for a NUMBER_TYPE field" do
      let(:base_type) { MetadataField::NUMBER_TYPE }

      it "returns the number error" do
        expect(helper.get_field_error(field)).to eq(ErrorHelper::NUMBER_INVALID_ERROR)
      end
    end

    context "for a STRING_TYPE field" do
      let(:base_type) { MetadataField::STRING_TYPE }

      it "lists valid options when force_options is set" do
        field.force_options = 1
        field.options = ["A", "B"].to_json
        expect(helper.get_field_error(field)).to eq("The valid options are A, B.")
      end

      it "returns a generic error when force_options is not set (0, the DB default)" do
        # get_field_error branches on `if field.force_options == 1`, matching the
        # model's own semantics (force_options is an integer column in [0, 1]).
        # Integer 0 is truthy in Ruby, so the previous `if field.force_options`
        # check wrongly hit the options branch for the default value (#294).
        field.force_options = 0
        expect(helper.get_field_error(field)).to eq("There was an error. Please contact us for help.")
      end
    end
  end

  describe ErrorHelper::ErrorAggregator do
    subject(:aggregator) { described_class.new }

    describe "#add_error" do
      it "raises for an unsupported error type" do
        expect { aggregator.add_error(:not_a_real_error, [1]) }
          .to raise_error(ArgumentError, /error type not supported/)
      end

      it "raises when the wrong number of params is provided" do
        # :row_missing_sample_name expects exactly one param (["Row #"]).
        expect { aggregator.add_error(:row_missing_sample_name, [1, 2]) }
          .to raise_error(ArgumentError, /wrong number of error params/)
      end

      it "accumulates errors of the same type" do
        aggregator.add_error(:row_missing_sample_name, [1])
        aggregator.add_error(:row_missing_sample_name, [2])
        groups = aggregator.error_groups
        expect(groups.length).to eq(1)
        expect(groups.first[:rows]).to eq([[1], [2]])
      end
    end

    describe "#error_groups" do
      it "returns an empty array with no errors" do
        expect(aggregator.error_groups).to eq([])
      end

      it "builds a caption via the title lambda using metadata and param count" do
        aggregator.set_metadata("num_cols", 5)
        aggregator.add_error(:row_wrong_num_values, [1, "sample_a", 3])
        aggregator.add_error(:row_wrong_num_values, [2, "sample_b", 4])
        group = aggregator.error_groups.first
        expect(group[:caption]).to include("2 rows have an unexpected number of values")
        expect(group[:caption]).to include("(5 values expected")
        expect(group[:headers]).to eq(["Row #", "Sample Name", "Number of Values"])
        expect(group[:isGroup]).to be(true)
      end
    end

    describe "#create_raw_value_error_group_for_metadata_field" do
      def build_field(base_type, opts = {})
        MetadataField.new({ name: "collection_field", display_name: "Collection Field", base_type: base_type }.merge(opts))
      end

      it "creates a location error group (non-human)" do
        field = build_field(MetadataField::LOCATION_TYPE)
        key = aggregator.create_raw_value_error_group_for_metadata_field(field, 3, false)
        expect(key).to eq("collection_field_invalid_raw_value")
        aggregator.add_error(key, [1, "s1", "bad"])
        expect(aggregator.error_groups.first[:caption]).to include(ErrorHelper::LOCATION_INVALID_ERROR)
      end

      it "creates a distinct human date error group key" do
        field = build_field(MetadataField::DATE_TYPE)
        key = aggregator.create_raw_value_error_group_for_metadata_field(field, 2, true)
        expect(key).to eq("collection_field_invalid_raw_value_human")
        aggregator.add_error(key, [1, "s1", "bad"])
        expect(aggregator.error_groups.first[:caption]).to include(ErrorHelper::DATE_INVALID_ERROR_HUMAN)
      end

      it "creates a number error group" do
        field = build_field(MetadataField::NUMBER_TYPE)
        key = aggregator.create_raw_value_error_group_for_metadata_field(field, 4, false)
        aggregator.add_error(key, [1, "s1", "bad"])
        expect(aggregator.error_groups.first[:caption]).to include(ErrorHelper::NUMBER_INVALID_ERROR)
      end

      it "creates a string error group listing options when force_options is set" do
        field = build_field(MetadataField::STRING_TYPE, force_options: 1, options: %w[X Y].to_json)
        key = aggregator.create_raw_value_error_group_for_metadata_field(field, 5, false)
        aggregator.add_error(key, [1, "s1", "bad"])
        expect(aggregator.error_groups.first[:caption]).to include("The valid options are X, Y.")
      end

      it "is idempotent for a repeated field/column key" do
        field = build_field(MetadataField::NUMBER_TYPE)
        key1 = aggregator.create_raw_value_error_group_for_metadata_field(field, 4, false)
        key2 = aggregator.create_raw_value_error_group_for_metadata_field(field, 4, false)
        expect(key1).to eq(key2)
      end
    end
  end
end

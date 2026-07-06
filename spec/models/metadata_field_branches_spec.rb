require 'rails_helper'

# Coverage Wave 2 (branch): metadata_field_spec.rb covers boolean?/validations/by_samples;
# this fills convert_type_to_string's type ladder, field_info nil-vs-present options,
# validated_field, default_for_host_genome?, add_examples dispatch, and the
# metadata_field_validations error branches.
describe MetadataField, type: :model do
  describe ".convert_type_to_string" do
    it "maps each known base type and falls through to empty string" do
      expect(MetadataField.convert_type_to_string(MetadataField::STRING_TYPE)).to eq("string")
      expect(MetadataField.convert_type_to_string(MetadataField::NUMBER_TYPE)).to eq("number")
      expect(MetadataField.convert_type_to_string(MetadataField::DATE_TYPE)).to eq("date")
      expect(MetadataField.convert_type_to_string(MetadataField::LOCATION_TYPE)).to eq("location")
      expect(MetadataField.convert_type_to_string(99)).to eq("")
    end
  end

  describe "#validated_field" do
    it "builds the *_validated_value column name from the base type" do
      field = build(:metadata_field, base_type: MetadataField::NUMBER_TYPE)
      expect(field.validated_field).to eq("number_validated_value")
    end
  end

  describe "#default_for_host_genome?" do
    it "is true when default_for_new_host_genome == 1" do
      field = build(:metadata_field, default_for_new_host_genome: 1)
      expect(field.default_for_host_genome?).to eq(true)
    end

    it "is false when default_for_new_host_genome == 0" do
      field = build(:metadata_field, default_for_new_host_genome: 0)
      expect(field.default_for_host_genome?).to eq(false)
    end
  end

  describe "#field_info" do
    it "parses options and examples when present" do
      field = create(:metadata_field, base_type: MetadataField::STRING_TYPE,
                                      options: '["DNA","RNA"]', examples: '{"all":["e1"]}')
      info = field.field_info
      expect(info[:options]).to eq(%w[DNA RNA])
      expect(info[:examples]).to eq("all" => ["e1"])
      expect(info[:dataType]).to eq("string")
    end

    it "leaves options and examples nil when absent" do
      field = create(:metadata_field, base_type: MetadataField::STRING_TYPE,
                                      options: nil, examples: nil)
      info = field.field_info
      expect(info[:options]).to be_nil
      expect(info[:examples]).to be_nil
    end
  end

  describe "#metadata_field_validations" do
    it "rejects a default field that is not core" do
      field = build(:metadata_field, is_default: 1, is_core: 0)
      expect(field).not_to be_valid
      expect(field.errors[:name].join).to match(/Default field must also be core/)
    end

    it "rejects a required field that is not default" do
      field = build(:metadata_field, is_required: 1, is_default: 0, is_core: 1)
      expect(field).not_to be_valid
      expect(field.errors[:name].join).to match(/Required field must also be default field/)
    end
  end

  describe "#add_examples" do
    let(:field) { create(:metadata_field, name: "custom_field") }

    it "adds examples under 'all' by default" do
      field.add_examples(["ex1"])
      expect(JSON.parse(field.reload.examples)).to eq("all" => ["ex1"])
    end

    it "raises for a host genome the field does not apply to" do
      expect { field.add_examples(["ex1"], "Nonexistent Host") }.to raise_error(/Invalid host genome/)
    end
  end
end

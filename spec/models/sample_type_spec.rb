require 'rails_helper'

RSpec.describe SampleType, type: :model do
  def build_sample_type(**attrs)
    SampleType.new({ name: "Plasma", group: "Systemic Inflammation" }.merge(attrs))
  end

  context "validations" do
    it "is valid with a name and a valid group" do
      expect(build_sample_type).to be_valid
    end

    it "requires a name" do
      st = build_sample_type(name: nil)
      expect(st).not_to be_valid
      expect(st.errors[:name]).to be_present
    end

    it "requires a group" do
      st = build_sample_type(group: nil)
      expect(st).not_to be_valid
      expect(st.errors[:group]).to be_present
    end

    it "enforces uniqueness of name" do
      build_sample_type(name: "Plasma").save!
      dup = build_sample_type(name: "Plasma")
      expect(dup).not_to be_valid
      expect(dup.errors[:name]).to be_present
    end

    it "rejects a group not in the allowed list" do
      st = build_sample_type(group: "Not A Real Group")
      expect(st).not_to be_valid
      expect(st.errors[:group]).to be_present
    end

    it "accepts each allowed group" do
      [
        'Systemic Inflammation', 'Central Nervous System', 'Respiratory Tract',
        'Reproductive Tract', 'Excrement', 'Organs', 'Insect Body Parts', 'Other'
      ].each do |group|
        st = build_sample_type(name: "Tissue", group: group)
        expect(st).to be_valid, "expected group #{group.inspect} to be valid"
      end
    end
  end

  context "name/group format" do
    it "rejects a name that does not start with a capital letter" do
      st = build_sample_type(name: "plasma")
      expect(st).not_to be_valid
      expect(st.errors[:name]).to be_present
    end

    it "rejects a name shorter than 3 chars" do
      st = build_sample_type(name: "Ab")
      expect(st).not_to be_valid
      expect(st.errors[:name]).to be_present
    end

    it "rejects a name longer than 30 chars" do
      st = build_sample_type(name: "A" + ("b" * 30))
      expect(st).not_to be_valid
      expect(st.errors[:name]).to be_present
    end

    it "allows word and space chars" do
      st = build_sample_type(name: "Cerebrospinal Fluid")
      expect(st).to be_valid
    end
  end
end

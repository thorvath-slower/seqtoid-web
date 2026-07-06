require 'rails_helper'

# Coverage Wave 2 (branch): user_setting_spec.rb only covers the happy boolean
# round-trip. This adds the invalid-key branch, the boolean validation failure
# branch, the value memoization (@value already set) branch, and the
# deserialize non-boolean fall-through.
describe UserSetting, type: :model do
  let(:joe) { create(:joe) }

  describe "#user_setting_checks" do
    it "rejects a key that is not in METADATA" do
      setting = build(:user_setting, key: "not_a_real_key", value: true, user: joe)
      expect(setting).not_to be_valid
      expect(setting.errors[:key].join).to match(/invalid/)
    end

    it "rejects a non-boolean value for a boolean setting" do
      setting = build(:user_setting, key: UserSetting::SHOW_SKIP_PROCESSING_OPTION,
                                     value: "maybe", user: joe)
      expect(setting).not_to be_valid
      expect(setting.errors[:value].join).to match(/must be true or false/)
    end

    it "accepts the string forms of true/false" do
      setting = build(:user_setting, key: UserSetting::SHOW_SKIP_PROCESSING_OPTION,
                                     value: "false", user: joe)
      expect(setting).to be_valid
    end
  end

  describe "#value" do
    it "returns the in-memory value without deserializing when @value is already set" do
      setting = build(:user_setting, key: UserSetting::SHOW_SKIP_PROCESSING_OPTION,
                                     value: true, user: joe)
      # @value present -> the `if @value.nil?` false branch, no deserialize.
      expect(setting).not_to receive(:deserialized_value)
      expect(setting.value).to eq(true)
    end

    it "leaves value nil when neither @value nor serialized_value is set" do
      setting = UserSetting.new(user: joe, key: UserSetting::SHOW_SKIP_PROCESSING_OPTION)
      expect(setting.value).to be_nil
    end
  end

  describe "serialization for a non-boolean-metadata key" do
    it "deserializes as the raw string when the key's data_type is not boolean" do
      stub_const("UserSetting::METADATA",
                 "string_setting" => { default: "x", description: "d", data_type: "string" })
      setting = create(:user_setting, key: "string_setting", serialized_value: "hello", user: joe)
      # deserialized_value's boolean branch is false -> returns serialized_value verbatim.
      expect(setting.value).to eq("hello")
    end
  end
end

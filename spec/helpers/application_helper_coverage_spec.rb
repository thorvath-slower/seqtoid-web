require "rails_helper"

# Characterization specs for ApplicationHelper methods not covered by the
# existing application_helper_spec (which only exercises #escape_json). Covers
# #rds_host, #hash_array_json2csv, the backslash-escaping branch of #escape_json,
# and #user_context (both the signed-in and signed-out paths). Spec-only.
RSpec.describe ApplicationHelper, type: :helper do
  describe "#rds_host" do
    it "returns the literal RDS address placeholder" do
      expect(helper.rds_host).to eq('$RDS_ADDRESS')
    end
  end

  describe "#hash_array_json2csv" do
    it "writes selected keys from a JSON array of hashes to a CSV file" do
      input = Tempfile.new(["input", ".json"])
      output = Tempfile.new(["output", ".csv"])
      begin
        input.write([
          { "a" => 1, "b" => 2, "c" => 3 },
          { "a" => 4, "b" => 5, "c" => 6 },
        ].to_json)
        input.flush

        helper.hash_array_json2csv(input.path, output.path, %w[a c])

        rows = CSV.read(output.path)
        expect(rows).to eq([["1", "3"], ["4", "6"]])
      ensure
        input.close!
        output.close!
      end
    end

    it "writes an empty CSV for an empty JSON array" do
      input = Tempfile.new(["input", ".json"])
      output = Tempfile.new(["output", ".csv"])
      begin
        input.write([].to_json)
        input.flush

        helper.hash_array_json2csv(input.path, output.path, %w[a])

        expect(File.read(output.path)).to eq("")
      ensure
        input.close!
        output.close!
      end
    end
  end

  describe "#escape_json backslash handling" do
    it "escapes embedded backslashes (exercising the str.include?('\\\\') branch)" do
      result = helper.escape_json({ "path" => 'C:\\temp\\x' })

      # The value contained backslashes, so the gsub! branch runs and the result
      # still round-trips back to the original data through the JS-literal +
      # JSON.parse layers the view uses.
      js_unescaped = result.gsub(/\\(['\\])/, '\1')
      expect(JSON.parse(js_unescaped)).to eq({ "path" => 'C:\\temp\\x' })
    end
  end

  describe "#user_context" do
    before do
      AppConfig.create!(key: AppConfig::AUTO_ACCOUNT_CREATION_V1, value: "1")
      AppConfig.create!(key: AppConfig::MAX_OBJECTS_BULK_DOWNLOAD, value: "500")
      AppConfig.create!(key: AppConfig::MAX_SAMPLES_BULK_DOWNLOAD_ORIGINAL_FILES, value: "10")
    end

    context "when a user is signed in" do
      let(:user) { create(:user, role: 0, sign_in_count: 1) }

      before { allow(helper).to receive(:current_user).and_return(user) }

      it "builds the signed-in user context hash" do
        context = helper.user_context

        expect(context[:userSignedIn]).to be(true)
        expect(context[:userId]).to eq(user.id)
        expect(context[:userName]).to eq(user.name)
        expect(context[:userEmail]).to eq(user.email)
        expect(context[:admin]).to be(false)
        expect(context[:firstSignIn]).to be(true)
        expect(context[:appConfig]).to include(:autoAccountCreationEnabled)
      end

      it "memoizes the context for the duration of the request" do
        first = helper.user_context
        expect(helper.user_context).to be(first)
      end

      it "flags admin users via role == 1" do
        admin = create(:admin, sign_in_count: 5)
        allow(helper).to receive(:current_user).and_return(admin)

        context = helper.user_context
        expect(context[:admin]).to be(true)
        expect(context[:firstSignIn]).to be(false)
      end
    end

    context "when no user is signed in" do
      before { allow(helper).to receive(:current_user).and_return(nil) }

      it "returns a signed-out context with empty defaults" do
        context = helper.user_context

        expect(context[:userSignedIn]).to be(false)
        expect(context[:admin]).to be(false)
        expect(context[:allowedFeatures]).to eq([])
        expect(context[:userId]).to be_nil
        expect(context[:firstSignIn]).to be_nil
      end
    end
  end
end

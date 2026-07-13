require "rails_helper"

RSpec.describe SampleAccessValidationService, type: :service do
  create_users

  before do
    # @joe's own project + sample (viewable to @joe)
    @joe_project = create(:project, users: [@joe])
    @joe_sample = create(:sample, project: @joe_project, user: @joe, name: "joe's sample")

    # A private project owned by another user; not viewable to @joe
    other_user = create(:user)
    @private_project = create(:project, users: [other_user])
    @private_sample = create(:sample, project: @private_project, user: other_user, name: "private sample")
  end

  describe "#call" do
    context "when the user has access to all requested samples" do
      it "returns the viewable Sample records with no error" do
        result = SampleAccessValidationService.call([@joe_sample.id], @joe)

        expect(result[:error]).to be_nil
        expect(result[:viewable_samples].map(&:id)).to contain_exactly(@joe_sample.id)
        # Returns Sample records, not ids
        expect(result[:viewable_samples].first).to be_a(Sample)
      end
    end

    context "when the user requests samples they cannot access" do
      it "filters out the inaccessible samples without raising an error" do
        result = SampleAccessValidationService.call([@joe_sample.id, @private_sample.id], @joe)

        expect(result[:error]).to be_nil
        expect(result[:viewable_samples].map(&:id)).to contain_exactly(@joe_sample.id)
      end
    end

    context "when none of the requested samples are accessible" do
      it "returns an empty viewable_samples array" do
        result = SampleAccessValidationService.call([@private_sample.id], @joe)

        expect(result[:error]).to be_nil
        expect(result[:viewable_samples]).to be_empty
      end
    end

    context "when query_ids is empty" do
      it "returns an empty viewable_samples array" do
        result = SampleAccessValidationService.call([], @joe)

        expect(result[:error]).to be_nil
        expect(result[:viewable_samples]).to be_empty
      end
    end

    context "when query_ids is nil" do
      it "treats it as an empty request and returns no samples" do
        result = SampleAccessValidationService.call(nil, @joe)

        expect(result[:error]).to be_nil
        expect(result[:viewable_samples]).to be_empty
      end
    end

    context "when query_ids are strings" do
      it "coerces them to integers and still resolves access" do
        result = SampleAccessValidationService.call([@joe_sample.id.to_s], @joe)

        expect(result[:error]).to be_nil
        expect(result[:viewable_samples].map(&:id)).to contain_exactly(@joe_sample.id)
      end
    end

    context "when an unexpected error occurs while validating access" do
      it "captures the error and returns SAMPLE_ACCESS_ERROR" do
        allow(Power).to receive(:new).and_raise(StandardError.new("boom"))

        result = SampleAccessValidationService.call([@joe_sample.id], @joe)

        expect(result[:error]).to eq(SampleAccessValidationService::SAMPLE_ACCESS_ERROR)
        expect(result[:viewable_samples]).to be_empty
      end
    end
  end
end

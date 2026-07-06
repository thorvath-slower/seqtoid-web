require "rails_helper"

RSpec.describe ComputeBackground, type: :job do
  describe "#perform" do
    let(:background) { create(:background) }

    it "invokes store_summary on the identified Background" do
      expect(Background).to receive(:find).with(background.id).and_return(background)
      expect(background).to receive(:store_summary)
      ComputeBackground.perform(background.id)
    end

    it "marks the background ready after storing the summary" do
      # `summarize` reads real taxon_counts; stub it so the job exercises the
      # store_summary DELETE/INSERT + `update(ready: 1)` path deterministically.
      allow(Background).to receive(:find).with(background.id).and_return(background)
      allow(background).to receive(:summarize).and_return([])
      expect(background.ready).not_to eq(1)
      ComputeBackground.perform(background.id)
      expect(background.reload.ready).to eq(1)
    end

    context "when store_summary fails" do
      before do
        allow(Background).to receive(:find).with(background.id).and_return(background)
        allow(background).to receive(:store_summary).and_raise(StandardError.new("boom"))
      end

      it "logs the error and re-raises so the on_failure hook fires" do
        expect(LogUtil).to receive(:log_error).with(
          "Background computation failed for background_id #{background.id}",
          background_id: background.id
        )
        expect do
          ComputeBackground.perform(background.id)
        end.to raise_error(StandardError, "boom")
      end
    end

    it "logs and raises RecordNotFound when the background does not exist" do
      expect(LogUtil).to receive(:log_error).with(
        "Background computation failed for background_id -1",
        background_id: -1
      )
      expect do
        ComputeBackground.perform(-1)
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end

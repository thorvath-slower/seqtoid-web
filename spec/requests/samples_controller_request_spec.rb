require 'rails_helper'

# Additional full-stack request specs for SamplesController, complementing
# spec/requests/sample_request_spec.rb. Targets the single-sample READ actions
# (set_sample scoping + 404 shape), the OWNER-only actions (check_owner), and a
# few of the batch collection endpoints that filter to viewable/owned samples.
# See app/controllers/samples_controller.rb (READ_ACTIONS / OWNER_ACTIONS /
# check_owner / set_sample).
RSpec.describe "Samples (extended) request", type: :request do
  create_users

  let(:illumina) { PipelineRun::TECHNOLOGY_INPUT[:illumina] }

  def sample_for(user, **attrs)
    project = create(:project, users: [user])
    create(:sample, project: project, user: user, **attrs)
  end

  describe "GET /samples/:id/metadata (READ, set_sample scoping)" do
    context "when not signed in" do
      it "returns 401 JSON (Warden failure_app)" do
        sample = sample_for(@joe)
        get "/samples/#{sample.id}/metadata"
        expect(response).to have_http_status(:unauthorized)
        expect(response.body).to include("Unauthorized")
      end
    end

    context "when signed in as a regular user" do
      before { sign_in @joe }

      it "returns metadata + additional_info for a viewable sample" do
        sample = sample_for(@joe, name: "Joe's sample")

        get "/samples/#{sample.id}/metadata"

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body).to have_key("metadata")
        expect(body["additional_info"]["name"]).to eq("Joe's sample")
        # The owner can edit their own sample.
        expect(body["additional_info"]["editable"]).to be(true)
      end

      it "returns a 404 (not a leak) for another user's private sample" do
        other = sample_for(@admin)

        get "/samples/#{other.id}/metadata"

        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)["error"]).to match(/isn't available/i)
      end

      it "returns 404 for a non-existent sample id" do
        get "/samples/0/metadata"
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /samples/:id (show)" do
    before { sign_in @joe }

    it "renders JSON for a viewable sample with editable=true for the owner" do
      sample = sample_for(@joe)

      get "/samples/#{sample.id}.json"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(sample.id)
      expect(body["editable"]).to be(true)
    end

    it "redirects to my_data for another user's private sample (set_sample redirect branch)" do
      other = sample_for(@admin)

      get "/samples/#{other.id}"

      expect(response).to redirect_to(my_data_path)
    end
  end

  describe "GET /samples/:id/results_folder.json (READ)" do
    before { sign_in @joe }

    it "returns the displayed data structure for a viewable sample" do
      sample = sample_for(@joe)
      create(:pipeline_run, sample: sample, technology: illumina, finalized: 1)

      get "/samples/#{sample.id}/results_folder.json"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to have_key("displayedData")
    end
  end

  describe "GET /samples/:id/raw_results_folder (OWNER-only, check_owner)" do
    it "returns 401 JSON for a viewable NON-owner (collaborator on a shared project)" do
      # A project shared between admin and joe: joe can VIEW admin's sample
      # (passes set_sample) but is not the uploader, so check_owner denies with 401.
      shared_project = create(:project, users: [@admin, @joe])
      admins_sample = create(:sample, project: shared_project, user: @admin)
      sign_in @joe

      get "/samples/#{admins_sample.id}/raw_results_folder"

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["message"]).to eq("Only the original uploader can access this.")
    end

    it "renders for the original uploader" do
      sample = sample_for(@joe)
      create(:pipeline_run, sample: sample, technology: illumina, finalized: 1)
      sign_in @joe

      get "/samples/#{sample.id}/raw_results_folder"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /samples/metadata_fields (collection, viewable scoping)" do
    before { sign_in @joe }

    it "returns metadata fields for a single viewable sample" do
      sample = sample_for(@joe)

      post "/samples/metadata_fields", params: { sampleIds: [sample.id] }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to be_an(Array)
    end

    it "ignores sample ids the user cannot view for multi-sample requests" do
      mine = sample_for(@joe)
      theirs = sample_for(@admin)

      post "/samples/metadata_fields", params: { sampleIds: [mine.id, theirs.id] }

      # No error, no leak: MetadataField.by_samples runs only over the viewable set.
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to be_an(Array)
    end
  end

  describe "POST /samples/uploaded_by_current_user" do
    before { sign_in @joe }

    it "reports true only when every id was uploaded by the current user" do
      mine = sample_for(@joe)

      post "/samples/uploaded_by_current_user", params: { sampleIds: [mine.id] }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["uploaded_by_current_user"]).to be(true)
    end

    it "reports false when an id was uploaded by another user" do
      mine = sample_for(@joe)
      theirs = sample_for(@admin)

      post "/samples/uploaded_by_current_user", params: { sampleIds: [mine.id, theirs.id] }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["uploaded_by_current_user"]).to be(false)
    end
  end

  describe "POST /samples/:id/save_metadata_v2 (EDIT)" do
    before { sign_in @joe }

    it "returns a failed status for an invalid metadata field on the owner's sample" do
      sample = sample_for(@joe)

      post "/samples/#{sample.id}/save_metadata_v2", params: { field: "not_a_real_field", value: "x" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["status"]).to eq("failed")
    end

    it "returns 404 when trying to edit another user's private sample (updatable scoping)" do
      other = sample_for(@admin)

      post "/samples/#{other.id}/save_metadata_v2", params: { field: "sample_type", value: "CSF" }

      expect(response).to have_http_status(:not_found)
    end
  end
end

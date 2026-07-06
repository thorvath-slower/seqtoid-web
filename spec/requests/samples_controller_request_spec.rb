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
      it "redirects to login for the HTML metadata endpoint (authenticate_user!)" do
        sample = sample_for(@joe)
        get "/samples/#{sample.id}/metadata"
        # No explicit format => HTML; authenticate_user! redirects rather than
        # rendering the Warden JSON 401 (that path is for JSON requests).
        expect(response).to have_http_status(:redirect)
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
      # Sample#default_background_id falls back to HostGenome.find_by(name: "Human")
      # when the sample's host genome has no default_background_id, so the show
      # JSON path requires a "Human" host genome to exist.
      create(:host_genome, name: "Human")
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
      # outputs_by_step drives SfnSingleStagePipelineDataService (WDL parsing),
      # which isn't available in the test env; stub it to a simple map so the
      # controller's folder-assembly + JSON render path is exercised.
      allow_any_instance_of(PipelineRun).to receive(:outputs_by_step).and_return({})

      get "/samples/#{sample.id}/results_folder.json"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to have_key("displayedData")
    end

    # CHARACTERIZATION (live Sentry, staging): SamplesController#results_folder
    # raised TypeError "no implicit conversion of Symbol into Integer" when
    # outputs_by_step indexes an array with a Symbol. We pin the CURRENT behavior:
    # the controller does NOT rescue it, so the error propagates (500 in prod).
    # DO NOT fix app code here — tracked as a separate Forgejo bug.
    it "propagates a TypeError from outputs_by_step (unrescued; pins Sentry behavior)" do
      sample = sample_for(@joe)
      create(:pipeline_run, sample: sample, technology: illumina, finalized: 1)
      allow_any_instance_of(PipelineRun).to receive(:outputs_by_step)
        .and_raise(TypeError.new("no implicit conversion of Symbol into Integer"))

      expect do
        get "/samples/#{sample.id}/results_folder.json"
      end.to raise_error(TypeError, /Symbol into Integer/)
    end
  end

  describe "GET /samples/:id/raw_results_folder (OWNER-only, check_owner)" do
    it "denies a viewable NON-owner with 401 (collaborator on a shared project)" do
      # A project shared between admin and joe: joe can VIEW admin's sample
      # (passes set_sample) but is not the uploader, so check_owner halts with 401.
      shared_project = create(:project, users: [@admin, @joe])
      admins_sample = create(:sample, project: shared_project, user: @admin)
      sign_in @joe

      get "/samples/#{admins_sample.id}/raw_results_folder"

      expect(response).to have_http_status(:unauthorized)
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

    it "surfaces the failed status when metadatum_add_or_update reports an error" do
      sample = sample_for(@joe)
      # metadatum_add_or_update auto-creates unknown fields, so drive the failure
      # branch explicitly to exercise the controller's error rendering.
      allow_any_instance_of(Sample).to receive(:metadatum_add_or_update)
        .and_return({ status: "error", error: "Invalid value" })

      post "/samples/#{sample.id}/save_metadata_v2", params: { field: "sample_type", value: "bogus" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("failed")
      expect(body["message"]).to eq("Invalid value")
    end

    it "returns 404 when trying to edit another user's private sample (updatable scoping)" do
      other = sample_for(@admin)

      post "/samples/#{other.id}/save_metadata_v2", params: { field: "sample_type", value: "CSF" }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /samples/:id/upload_credentials (OWNER-only)" do
    # CHARACTERIZATION (live Sentry, dev): SamplesController#upload_credentials
    # hit Aws::STS::Errors::AccessDenied when the STS credential vend failed. The
    # controller does NOT rescue it today, so the error propagates. We pin that
    # behavior; DO NOT fix app code here (tracked as a separate Forgejo bug).
    it "propagates a credential-vend error (pins Sentry AccessDenied behavior)" do
      # Live Sentry raised Aws::STS::Errors::AccessDenied here; that class isn't
      # guaranteed loadable in the test env, so we stand in a generic error to
      # pin the same fact: get_upload_credentials failures are NOT rescued and
      # propagate out of the action (500 in prod).
      sample = sample_for(@joe, status: Sample::STATUS_CREATED)
      sign_in @joe
      allow_any_instance_of(SamplesController).to receive(:get_upload_credentials)
        .and_raise(StandardError.new("Access denied (stands in for Aws::STS::Errors::AccessDenied)"))

      expect do
        get "/samples/#{sample.id}/upload_credentials.json"
      end.to raise_error(StandardError, /Access denied/)
    end

    it "returns 401 for an already-uploaded sample (not in CREATED status)" do
      sample = sample_for(@joe, status: Sample::STATUS_CHECKED)
      sign_in @joe

      get "/samples/#{sample.id}/upload_credentials.json"

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["error"]).to eq("This sample was already uploaded.")
    end
  end
end

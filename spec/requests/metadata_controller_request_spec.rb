require 'rails_helper'

# Full-stack request specs for MetadataController.
#
# The existing spec/controllers/metadata_controller_spec.rb (type: :controller)
# covers the happy paths for metadata_template_csv and metadata_for_host_genome.
# These request specs fill the gaps: the unauthenticated-allowed actions
# (dictionary, instructions, official_metadata_fields), the auth gate on the
# rest, and both branches of validate_csv_for_new_samples (success + rescue).
# See app/controllers/metadata_controller.rb.
RSpec.describe "Metadata request", type: :request do
  create_users

  describe "GET /metadata/official_metadata_fields (skip auth)" do
    it "is reachable without signing in and returns JSON" do
      create(:metadata_field, is_core: 1, is_default: 1)

      get "/metadata/official_metadata_fields"

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
      expect(JSON.parse(response.body)).to be_an(Array)
    end
  end

  describe "GET /metadata/dictionary (skip auth)" do
    it "renders the discovery view router without auth" do
      get "/metadata/dictionary"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /metadata/instructions" do
    it "requires authentication" do
      get "/metadata/instructions"
      # HTML action: unauthenticated users are redirected to login (302 Found),
      # not given a 401 JSON body.
      expect(response).to have_http_status(:found)
    end

    it "renders for a signed-in user" do
      sign_in @joe
      get "/metadata/instructions"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /metadata/metadata_for_host_genome" do
    it "requires authentication" do
      get "/metadata/metadata_for_host_genome", params: { name: "Human" }
      # Unauthenticated request is redirected to login (302 Found).
      expect(response).to have_http_status(:found)
    end

    it "returns not_found when the host genome does not exist" do
      sign_in @joe
      get "/metadata/metadata_for_host_genome", params: { name: "does-not-exist" }
      expect(response).to have_http_status(:not_found)
    end

    it "returns the host genome metadata fields when found" do
      sign_in @joe
      mf = create(:metadata_field)
      hg = create(:host_genome, metadata_fields: [mf.name])

      get "/metadata/metadata_for_host_genome", params: { name: hg.name }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.map { |x| x["name"] }).to include(mf.name)
    end
  end

  describe "POST /metadata/validate_csv_for_new_samples" do
    before { sign_in @joe }

    it "returns a success payload when validation runs" do
      project = create(:project, users: [@joe])
      create(:host_genome, name: "Human")

      # Send as JSON: the payload has nested arrays (metadata rows, samples),
      # which only round-trip through JSON encoding. This mirrors the real
      # frontend, which POSTs a JSON body.
      post "/metadata/validate_csv_for_new_samples", params: {
        metadata: {
          "headers" => ["sample_name", "Host Organism"],
          "rows" => [["sample_a", "Human"]],
        },
        samples: [{ "name" => "sample_a", "project_id" => project.id }],
      }, as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("success")
      expect(json).to have_key("issues")
      expect(json).to have_key("newHostGenomes")
    end

    it "returns an error payload (422) when the request raises" do
      # samples param omitted -> samples_data is nil -> .map raises ->
      # rescue branch renders status: error with :unprocessable_content.
      post "/metadata/validate_csv_for_new_samples", params: {
        metadata: { "headers" => ["Sample Name"] },
      }

      expect(response).to have_http_status(422)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json["issues"]).to have_key("errors")
    end
  end

  describe "POST /metadata/metadata_template_csv with host_genomes branch" do
    before { sign_in @joe }

    it "includes fields from a manually specified host genome" do
      create(:metadata_field, name: "collection_location_v2", display_name: "Collection Location", is_core: 1, is_default: 1, is_required: 1, default_for_new_host_genome: 1)
      mf = create(:metadata_field)
      hg = create(:host_genome, metadata_fields: [mf.name])

      post "/metadata/metadata_template_csv", params: {
        new_sample_names: ["foo"],
        host_genomes: [hg.name],
      }

      expect(response).to have_http_status(:ok)
      csv = CSV.new(response.body).read
      expect(csv.first).to include(mf.display_name)
    end
  end
end

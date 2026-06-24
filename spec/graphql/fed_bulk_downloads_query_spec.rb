require "rails_helper"

# CZID-285 (303c): native Rails GraphQL port of the federation fedBulkDownloads op.
# Mirrors BulkDownloadsController#index + format_bulk_download, then the federation
# mapping (status enum, entityInputs concat, params filter/camelize).
RSpec.describe GraphqlController, type: :request do
  create_users

  FED_BULK_DOWNLOADS_QUERY = <<GQL
  query BulkDownloadListQuery {
    fedBulkDownloads {
      id
      status
      startedAt
      ownerUserId
      downloadType
      analysisCount
      url
      fileSize
      entityInputFileType
      logUrl
      errorMessage
      entityInputs {
        id
        name
      }
      params {
        paramType
        value
        displayName
      }
    }
  }
GQL

  def post_query
    post "/graphql", headers: { "Content-Type" => "application/json" }, params: {
      query: FED_BULK_DOWNLOADS_QUERY,
    }.to_json
  end

  context "Joe (non-admin)" do
    before { sign_in @joe }

    it "maps the viewable bulk downloads to the federation shape" do
      project = create(:project, users: [@joe])
      sample = create(:sample, project: project, user: @joe, name: "CG Sample")
      wr = create(:workflow_run, sample: sample, user: @joe, workflow: WorkflowRun::WORKFLOW[:consensus_genome])

      bulk_download = create(:bulk_download,
                             download_type: "consensus_genome",
                             status: "waiting",
                             user: @joe,
                             params: {
                               "download_format" => { "paramType" => "string", "displayName" => "Download Format", "value" => "Separate Files" },
                               "workflow" => { "value" => "consensus-genome" },
                               "sample_ids" => { "value" => [1, 2] },
                             })
      bulk_download.workflow_runs << wr
      allow_any_instance_of(BulkDownload).to receive(:output_file_presigned_url).and_return("https://example.test/presigned")

      post_query

      expect(response).to have_http_status(:success)
      parsed = JSON.parse(response.body)
      expect(parsed["errors"]).to(be_nil, "GraphQL errors: #{parsed['errors']}")

      data = parsed.dig("data", "fedBulkDownloads")
      expect(data.length).to eq(1)
      bd = data.first

      expect(bd).to include(
        "id" => bulk_download.id.to_s,
        "status" => "PENDING",
        "downloadType" => "consensus_genome",
        "ownerUserId" => @joe.id,
        "analysisCount" => 1,
        "url" => "https://example.test/presigned",
        "entityInputFileType" => "consensus-genome",
        "logUrl" => nil
      )
      # entityInputs = workflow runs (then pipeline runs)
      expect(bd["entityInputs"]).to eq([{ "id" => wr.id.to_s, "name" => "CG Sample" }])
      # params: download_format kept + camelized; workflow/sample_ids dropped
      expect(bd["params"]).to eq([
        { "paramType" => "downloadFormat", "displayName" => "Download Format", "value" => "Separate Files" },
      ])
    end

    it "returns an empty list when the user has no bulk downloads" do
      post_query

      parsed = JSON.parse(response.body)
      expect(parsed["errors"]).to(be_nil, "GraphQL errors: #{parsed['errors']}")
      expect(parsed.dig("data", "fedBulkDownloads")).to eq([])
    end
  end
end

require "rails_helper"

# CZID-285 (303b): native Rails GraphQL port of the federation fedConsensusGenomes op.
# Covers both modes: the single-CG-result report (where.producingRunId._eq) and the thin
# discovery row ({ sequencingRead: { id } }).
RSpec.describe GraphqlController, type: :request do
  create_users

  SINGLE_RESULT_QUERY = <<GQL
  query ConsensusGenomeReportQuery($input: queryInput_fedConsensusGenomes_input_Input) {
    fedConsensusGenomes(input: $input) {
      taxon {
        id
        name
        commonName
      }
      accession {
        accessionId
        accessionName
      }
      metrics {
        coverageDepth
        coverageBreadth
        coverageTotalLength
        coverageViz
        coverageBinSize
        gcPercent
        percentGenomeCalled
        percentIdentity
        refSnps
        nMissing
        nAmbiguous
        nActg
        mappedReads
      }
      referenceGenome {
        file {
          downloadLink {
            url
          }
        }
      }
    }
  }
GQL

  DISCOVERY_IDS_QUERY = <<GQL
  query DiscoveryViewFCConsensusGenomeIdsQuery($input: queryInput_fedConsensusGenomes_input_Input) {
    fedConsensusGenomes(input: $input) {
      producingRunId
      sequencingRead {
        id
      }
    }
  }
GQL

  def post_query(query, variables)
    post "/graphql", headers: { "Content-Type" => "application/json" }, params: {
      query: query,
      variables: variables,
    }.to_json
  end

  context "Joe" do
    before { sign_in @joe }

    it "maps a single consensus-genome result (where.producingRunId._eq)" do
      project = create(:project, users: [@joe])
      sample = create(:sample, project: project, user: @joe)
      wr = create(:workflow_run,
                  sample: sample,
                  user: @joe,
                  workflow: WorkflowRun::WORKFLOW[:consensus_genome])

      allow_any_instance_of(ConsensusGenomeWorkflowRun).to receive(:results).and_return(
        coverage_viz: {
          "total_length" => 29_903,
          "coverage_depth" => 12.5,
          "coverage_breadth" => 0.98,
          "coverage_bin_size" => 50.0,
          "coverage" => [[0.0, 10.0], [1.0, 12.0]],
        },
        quality_metrics: {
          "gc_percent" => 38.0,
          "percent_genome_called" => 99.1,
          "percent_identity" => 99.9,
          "ref_snps" => 3,
          "n_missing" => 1,
          "n_ambiguous" => 0,
          "n_actg" => 29_900,
          "mapped_reads" => 50_000,
        },
        taxon_info: {
          "accession_id" => "MN908947.3",
          "accession_name" => "SARS-CoV-2",
          "taxon_id" => 2_697_049,
          "taxon_name" => "Severe acute respiratory syndrome coronavirus 2",
        }
      )

      post_query(SINGLE_RESULT_QUERY, input: { where: { producingRunId: { _eq: wr.id.to_s } } })

      expect(response).to have_http_status(:success)
      parsed = JSON.parse(response.body)
      expect(parsed["errors"]).to(be_nil, "GraphQL errors: #{parsed['errors']}")

      data = parsed.dig("data", "fedConsensusGenomes")
      expect(data.length).to eq(1)
      cg = data.first

      expect(cg["taxon"]).to eq(
        "id" => "2697049",
        "name" => "Severe acute respiratory syndrome coronavirus 2",
        "commonName" => "Severe acute respiratory syndrome coronavirus 2"
      )
      expect(cg["accession"]).to eq("accessionId" => "MN908947.3", "accessionName" => "SARS-CoV-2")
      expect(cg["metrics"]).to include(
        "coverageDepth" => 12.5,
        "coverageBreadth" => 0.98,
        "coverageTotalLength" => 29_903.0,
        "coverageBinSize" => 50.0,
        "coverageViz" => [[0.0, 10.0], [1.0, 12.0]],
        "gcPercent" => 38.0,
        "refSnps" => 3,
        "nActg" => 29_900,
        "mappedReads" => 50_000
      )
      # No reference_sequence input file on the sample -> nil download url.
      expect(cg.dig("referenceGenome", "file", "downloadLink", "url")).to be_nil
    end

    it "maps discovery consensus genomes to { sequencingRead: { id } } (producingRunId null)" do
      project = create(:project, users: [@joe])
      sample = create(:sample, project: project, user: @joe)
      create(:workflow_run,
             sample: sample,
             user: @joe,
             workflow: WorkflowRun::WORKFLOW[:consensus_genome])

      post_query(DISCOVERY_IDS_QUERY, input: { todoRemove: { domain: "my_data", workflow: "consensus-genome" } })

      expect(response).to have_http_status(:success)
      parsed = JSON.parse(response.body)
      expect(parsed["errors"]).to(be_nil, "GraphQL errors: #{parsed['errors']}")

      data = parsed.dig("data", "fedConsensusGenomes")
      expect(data.length).to eq(1)
      expect(data.first["producingRunId"]).to be_nil
      expect(data.first.dig("sequencingRead", "id")).to eq(sample.id.to_s)
    end
  end
end

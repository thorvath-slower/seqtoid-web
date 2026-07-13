module Queries
  # Ported from the GraphQL federation server (resolver-functions/fedConsensusGenomes) as
  # part of CZID-285 (303b). Two modes, matching the federation resolver:
  #
  #   1. Single CG result (input.where.producingRunId._eq): mirrors GET
  #      /workflow_runs/:id/results + the ref_fasta branch of
  #      WorkflowRunsController#cg_report_downloads, mapped to the CG report shape.
  #   2. Discovery (otherwise): runs the shared WorkflowRunsFetching pipeline
  #      (mode: basic) and maps each run to { sequencingRead: { id } } -- exactly what
  #      the federation discovery branch returned (producingRunId stays null).
  module FedConsensusGenomesQuery
    extend ActiveSupport::Concern
    include PipelineOutputsHelper # get_presigned_s3_url

    included do
      field :fedConsensusGenomes,
            [Types::FedConsensusGenomesType],
            null: true,
            camelize: false,
            resolver_method: :resolve_fed_consensus_genomes do
        argument :input, Types::FedConsensusGenomesInputType, required: false
      end
    end

    def resolve_fed_consensus_genomes(input: nil)
      raise GraphQL::ExecutionError, "fedConsensusGenomes input was nullish" if input.nil?

      producing_run_id = input.where&.producingRunId&._eq
      return [single_consensus_genome_result(producing_run_id)] if producing_run_id.present?

      td = input.todoRemove
      result = discovery_workflow_runs(
        domain: td&.domain,
        filters: {
          search: td&.search,
          host: td&.host,
          locationV2: td&.location_v2,
          tissue: td&.tissue,
          projectId: td&.project_id,
          visibility: td&.visibility,
          time: td&.time,
          workflow: td&.workflow,
          taxon: td&.taxons,
          sampleIds: td&.sample_ids,
          workflowRunIds: td&.workflow_run_ids,
        },
        mode: "basic",
        order_by: td&.order_by,
        order_dir: td&.order_dir,
        offset: 0,
        limit: Queries::FedWorkflowRunsQuery::DISCOVERY_LIMIT
      )

      result[:workflow_runs].as_json.map do |run|
        { sequencingRead: { id: run.dig("sample", "info", "id")&.to_s } }
      end
    end

    private

    def single_consensus_genome_result(workflow_run_id)
      workflow_run = current_power.workflow_runs.find(workflow_run_id)
      workflow_class = WorkflowRun::WORKFLOW_CLASS[workflow_run.workflow]
      workflow_run = workflow_class ? workflow_run.becomes(workflow_class) : workflow_run

      data = workflow_run.results.as_json
      coverage_viz = data["coverage_viz"] || {}
      quality_metrics = data["quality_metrics"] || {}
      taxon_info = data["taxon_info"] || {}

      accession_id = taxon_info["accession_id"]
      accession_name = taxon_info["accession_name"]
      taxon_id = taxon_info["taxon_id"]
      taxon_name = taxon_info["taxon_name"]

      accession =
        if accession_id && accession_name
          { accessionId: accession_id, accessionName: accession_name }
        end
      taxon =
        if taxon_id && taxon_name
          { id: taxon_id.to_s, name: taxon_name, commonName: taxon_name }
        end

      {
        metrics: {
          coverageTotalLength: coverage_viz["total_length"],
          coverageDepth: coverage_viz["coverage_depth"],
          coverageBreadth: coverage_viz["coverage_breadth"],
          coverageBinSize: coverage_viz["coverage_bin_size"],
          coverageViz: coverage_viz["coverage"],
          gcPercent: quality_metrics["gc_percent"],
          percentGenomeCalled: quality_metrics["percent_genome_called"],
          percentIdentity: quality_metrics["percent_identity"],
          refSnps: quality_metrics["ref_snps"],
          nMissing: quality_metrics["n_missing"],
          nAmbiguous: quality_metrics["n_ambiguous"],
          nActg: quality_metrics["n_actg"],
          mappedReads: quality_metrics["mapped_reads"],
        },
        accession: accession,
        taxon: taxon,
        referenceGenome: {
          file: {
            downloadLink: {
              url: reference_genome_download_url(workflow_run),
            },
          },
        },
      }
    end

    # Mirrors the ref_fasta branch of WorkflowRunsController#cg_report_downloads.
    def reference_genome_download_url(workflow_run)
      s3_path = workflow_run.sample.input_files.reference_sequence[0]&.s3_path
      filename = workflow_run.inputs&.[]("ref_fasta")
      return nil unless s3_path.present? && filename.present?

      get_presigned_s3_url(
        s3_path: s3_path,
        filename: "#{workflow_run.sample.name}_#{workflow_run.id}_#{filename}"
      )
    end
  end
end

module Queries
  # Ported from the GraphQL federation server (resolver-functions/fedWorkflowRuns) as
  # part of CZID-285 (303b). Serves the DISCOVERY-VIEW mode of `fedWorkflowRuns` natively
  # from Rails instead of proxying GET /workflow_runs.json. Reuses the shared
  # WorkflowRunsFetching pipeline (the same code /workflow_runs.json runs) and then
  # applies the federation resolver's exact mapping over the JSON-serialized output.
  #
  # NOT yet ported (separate follow-up): the CG bulk-download-modal mode
  # (input.where.id._in), which the federation served by POSTing to
  # /workflow_runs/valid_consensus_genome_workflow_runs — an endpoint that does not exist
  # in this Rails app. That mode raises a clear error here rather than returning wrong data.
  module FedWorkflowRunsQuery
    extend ActiveSupport::Concern

    # The federation passed limit: TEN_MILLION to fetch the full discovery result set.
    DISCOVERY_LIMIT = 10_000_000

    included do
      field :fedWorkflowRuns,
            [Types::FedWorkflowRunsType],
            null: true,
            camelize: false,
            resolver_method: :resolve_fed_workflow_runs do
        argument :input, Types::FedWorkflowRunsInputType, required: false
      end
    end

    def resolve_fed_workflow_runs(input: nil)
      raise GraphQL::ExecutionError, "fedWorkflowRuns input is nullish" if input.nil?

      if input.where&.id&._in.present?
        raise GraphQL::ExecutionError,
              "fedWorkflowRuns bulk consensus-genome validation (where.id._in) is not yet " \
              "ported to Rails-native GraphQL (CZID-285 follow-up)."
      end

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
          taxon: td&.taxon,
        },
        mode: "basic",
        order_by: td&.order_by,
        order_dir: td&.order_dir,
        offset: 0,
        limit: DISCOVERY_LIMIT
      )

      # Serialize exactly as /workflow_runs.json did (Times -> ISO strings, symbol ->
      # string keys) so the mapping sees what the federation saw over the wire.
      result[:workflow_runs].as_json.map { |run| map_fed_workflow_run(run) }
    end

    private

    def map_fed_workflow_run(run)
      creation_source = run.dig("inputs", "creation_source")
      sample_id = run.dig("sample", "info", "id")

      {
        id: run["id"].to_s,
        ownerUserId: run.dig("runner", "id"),
        startedAt: run["created_at"],
        status: run["status"],
        errorLabel: nil,
        rawInputsJson: %({"creation_source": "#{creation_source}"}),
        workflowVersion: {
          version: run["wdl_version"],
          workflow: {
            name: creation_source,
          },
        },
        entityInputs: {
          edges: [
            {
              node: {
                entityType: "sequencing_read",
                inputEntityId: sample_id&.to_s,
              },
            },
          ],
        },
      }
    end
  end
end

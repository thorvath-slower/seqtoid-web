module Queries
  # Ported from the GraphQL federation server (resolver-functions/fedWorkflowRuns) as
  # part of CZID-285. Serves `fedWorkflowRuns` natively from Rails. Two modes, matching
  # the federation resolver:
  #
  #   1. CG bulk-download-modal (input.where.id._in): validate a set of workflow run ids
  #      down to the viewable, non-deprecated consensus-genome runs and return minimal
  #      {id, ownerUserId, status}. The federation served this via POST
  #      /workflow_runs/valid_consensus_genome_workflow_runs, an action removed in CZID-283
  #      (NextGen cleanup) whose only consumer was the federation -- so this resolver is now
  #      its authoritative home, reproducing the removed action's exact contract
  #      (WorkflowRunValidationService + by_workflow(CG).non_deprecated). CZID-309.
  #   2. Discovery view (otherwise): reuses the shared WorkflowRunsFetching pipeline (the
  #      same code /workflow_runs.json runs), mapped over its JSON-serialized output (303b).
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

      return valid_consensus_genome_workflow_runs(input.where.id._in) if input.where&.id&._in.present?

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

    # CG bulk-download-modal validation. Reproduces the removed
    # WorkflowRunsController#valid_consensus_genome_workflow_runs exactly: access-validate
    # the ids (WorkflowRunValidationService), keep the non-deprecated consensus-genome
    # runs, and return {id (stringified), ownerUserId (user_id), status (raw)}. Returns []
    # on an access-validation error, matching the federation's empty-on-error behavior.
    def valid_consensus_genome_workflow_runs(workflow_run_ids)
      validated = WorkflowRunValidationService.call(query_ids: workflow_run_ids, current_user: current_user)
      return [] unless validated[:error].nil?

      validated[:viewable_workflow_runs]
        .by_workflow(WorkflowRun::WORKFLOW[:consensus_genome])
        .non_deprecated
        .pluck(:id, :user_id, :status)
        .map { |id, user_id, status| { id: id.to_s, ownerUserId: user_id, status: status } }
    end

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

module Queries
  # Ported from the GraphQL federation server (resolver-functions/fedWorkflowRunsAggregate
  # + utils/aggregateUtils processWorkflowsAggregateResponse) as part of CZID-285 (303c).
  # Serves the DiscoveryView per-project per-workflow run counts natively instead of
  # proxying GET /projects.json. Reuses the shared ProjectsDiscovery pipeline (the same
  # code /projects.json runs) so the sample_counts are byte-identical, then emits the
  # aggregate/groupBy entries the federation built (3 workflows per project), optionally
  # restricted to where.collectionId._in.
  module FedWorkflowRunsAggregateQuery
    extend ActiveSupport::Concern

    # Maps the federation's workflow names to the project sample_counts keys, in the
    # federation's emission order.
    WORKFLOW_COUNT_KEYS = {
      "consensus-genome" => "cg_runs_count",
      "short-read-mngs" => "mngs_runs_count",
      "amr" => "amr_runs_count",
    }.freeze

    included do
      field :fedWorkflowRunsAggregate,
            Types::FedWorkflowRunsAggregateType,
            null: true,
            camelize: false,
            resolver_method: :resolve_fed_workflow_runs_aggregate do
        argument :input, Types::FedWorkflowRunsAggregateInputType, required: false
      end
    end

    def resolve_fed_workflow_runs_aggregate(input: nil)
      td = input&.todoRemove
      paginated_ids = input&.where&.collectionId&._in
      paginated_ids = paginated_ids.to_set if paginated_ids.present?

      scope = discovery_projects_scope(
        domain: td&.domain,
        project_id: td&.project_id,
        search: td&.search,
        sample_filters: aggregate_sample_filters(td),
        sorting_v0_allowed: false,
        order_by: :id,
        order_dir: :desc
      )
      projects = format_discovery_projects(scope)

      aggregate = []
      projects.each do |project|
        next if paginated_ids && !paginated_ids.include?(project["id"])

        counts = project["sample_counts"] || {}
        WORKFLOW_COUNT_KEYS.each_key do |workflow|
          aggregate << {
            groupBy: {
              workflowVersion: { workflow: { name: workflow } },
              collectionId: project["id"],
            },
            count: counts[WORKFLOW_COUNT_KEYS[workflow]],
          }
        end
      end

      { aggregate: aggregate }
    end

    private

    # The discovery filters forwarded to the projects scope, mirroring the params the
    # federation put on /projects.json. Only present (non-blank) keys are included so the
    # scope's `key?`-gated sample-filter join matches the controller exactly.
    def aggregate_sample_filters(td)
      return {} if td.nil?

      {
        host: td.host,
        locationV2: td.location_v2,
        taxon: td.taxon,
        taxaLevels: td.taxa_levels,
        taxonThresholds: td.taxon_thresholds&.map(&:to_h),
        annotations: td.annotations&.map(&:to_h),
        time: td.time,
        tissue: td.tissue,
        visibility: td.visibility,
      }.select { |_, value| value.present? }
    end
  end
end

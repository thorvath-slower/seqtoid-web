module Queries
  # Ported from the GraphQL federation server
  # (resolver-functions/fedWorkflowRunsAggregateTotalCount) as part of CZID-285 (303c).
  # Serves the DiscoveryView per-workflow total counts natively instead of proxying
  # GET /samples/stats.json. Reproduces SamplesController#stats' countByWorkflow (the
  # federation forwarded only domain + projectId) using the shared SamplesHelper scopes,
  # then shapes it into the aggregate/groupBy response the federation built.
  module FedWorkflowRunsAggregateTotalCountQuery
    extend ActiveSupport::Concern

    included do
      field :fedWorkflowRunsAggregateTotalCount,
            Types::FedWorkflowRunsAggregateTotalCountType,
            null: true,
            camelize: false,
            resolver_method: :resolve_fed_workflow_runs_aggregate_total_count do
        argument :input, Types::FedWorkflowRunsAggregateTotalCountInputType, required: false
      end
    end

    def resolve_fed_workflow_runs_aggregate_total_count(input: nil)
      td = input&.todoRemove

      samples = samples_by_domain(td&.domain)
      samples = filter_samples(samples, { projectId: td&.project_id }).non_deleted
      samples_workflow_runs = current_power.samples_workflow_runs(samples).non_deprecated.non_deleted

      count_by_workflow = {
        WorkflowRun::WORKFLOW[:short_read_mngs] => samples.where(initial_workflow: WorkflowRun::WORKFLOW[:short_read_mngs]).distinct.count,
        WorkflowRun::WORKFLOW[:long_read_mngs] => samples.where(initial_workflow: WorkflowRun::WORKFLOW[:long_read_mngs]).distinct.count,
        WorkflowRun::WORKFLOW[:consensus_genome] => samples_workflow_runs.by_workflow(WorkflowRun::WORKFLOW[:consensus_genome]).count,
        WorkflowRun::WORKFLOW[:amr] => samples_workflow_runs.by_workflow(WorkflowRun::WORKFLOW[:amr]).count,
        WorkflowRun::WORKFLOW[:benchmark] => samples_workflow_runs.by_workflow(WorkflowRun::WORKFLOW[:benchmark]).count,
      }

      aggregate = count_by_workflow.map do |workflow_name, count|
        {
          groupBy: { workflowVersion: { workflow: { name: workflow_name } } },
          count: count,
        }
      end

      { aggregate: aggregate }
    end
  end
end

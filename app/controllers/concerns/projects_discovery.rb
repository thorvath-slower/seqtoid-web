# Shared discovery-view project fetch + per-project sample_counts serialization.
#
# Extracted from ProjectsController#index (CZID-285, 303c) so the Rails REST endpoint
# (/projects.json) and the Rails-native fedWorkflowRunsAggregate resolver run the SAME
# code and return byte-identical per-project workflow counts. Behavior is unchanged for
# the controller — the logic and field shapes are preserved exactly.
#
# Hosts that include this concern must provide `current_user`, `current_power`,
# `filter_samples` (SamplesHelper), and `Project.sort_projects` / `search_by_name`.
module ProjectsDiscovery
  extend ActiveSupport::Concern

  # The few fields returned for every project (and the basis for sample_counts).
  def discovery_project_basic_attributes
    [
      "id", "name", "description", "created_at", "public_access",
      Arel.sql("COUNT(DISTINCT samples.id) AS number_of_samples"),
    ]
  end

  # The filtered + sorted (pre-limit) projects relation, exactly as
  # ProjectsController#index builds it. `sample_filters` responds to `key?` and is passed
  # to filter_samples (ActionController::Parameters from the controller, a Hash from the
  # resolver).
  def discovery_projects_scope(domain:, project_id:, search:, sample_filters:, sorting_v0_allowed:, order_by:, order_dir:)
    projects = current_power.projects_by_domain(domain)

    # including these early ensures that users and samples are joined in the same order,
    # making rails assign deterministic aliases
    projects = projects.includes(:users).includes(:samples)
    projects = projects.where(id: project_id) if project_id
    projects = projects.search_by_name(search) if search
    if [:host, :location, :locationV2, :taxon, :time, :tissue, :annotations].any? { |key| sample_filters.key?(key) }
      projects = projects.where(samples: { id: filter_samples(current_power.samples, sample_filters) })
    elsif sample_filters.key?(:visibility)
      access_to_project = sample_filters[:visibility] == "public"
      projects = projects.where(public_access: access_to_project)
    end

    if sorting_v0_allowed
      Project.sort_projects(projects, order_by, order_dir)
    else
      projects.order(Hash[order_by => order_dir])
    end
  end

  # Serialize the given (already limited/offset, if applicable) projects relation into the
  # detailed project hashes — including the sample_counts aggregate — exactly as the
  # non-basic branch of ProjectsController#index does.
  def format_discovery_projects(projects_scope)
    # Postgres requires every non-aggregated selected column to appear in GROUP BY
    # (MySQL relaxed this). Besides projects.id (the PK, which functionally determines
    # the other projects.* columns), this query also selects the non-aggregated creator
    # columns from the second users join (aliased creators_projects), so they must be
    # grouped too.
    projects_scope = projects_scope
                     .includes(:creator, samples: [:host_genome, :user, { metadata: [:metadata_field, :location] }, :pipeline_runs, :workflow_runs])
                     .group("projects.id", "creators_projects.id", "creators_projects.name")
                     .references(:pipeline_runs, :samples, :workflow_runs)
    # aggregated lists of association values as strings. Portable string_agg
    # (Postgres/MySQL 8+); separator '::', and DISTINCT aggregates order by the
    # aggregated expression itself (Postgres requires the ORDER BY key to be in
    # the argument list). bug-#011.
    group_concat_host = Arel.sql("GROUP_CONCAT(DISTINCT host_genomes.name ORDER BY host_genomes.name SEPARATOR '::') AS hosts")
    group_concat_sample_type = Arel.sql("GROUP_CONCAT(DISTINCT CASE WHEN metadata_fields.name = 'sample_type' THEN metadata.string_validated_value ELSE NULL END ORDER BY 1 SEPARATOR '::') AS sample_types")
    group_concat_location = Arel.sql("GROUP_CONCAT(DISTINCT CASE WHEN metadata_fields.name = 'collection_location' THEN IFNULL(locations.name, metadata.string_validated_value) ELSE NULL END SEPARATOR '::') AS locations")
    # Use || (not CONCAT): Postgres CONCAT ignores NULLs and would emit a
    # partial "|email" for null-user rows, whereas MySQL CONCAT returns NULL
    # (skipped by the aggregate). || preserves that NULL-if-any-NULL semantics.
    group_concat_users = Arel.sql("GROUP_CONCAT(DISTINCT CONCAT(users.name,'|',users.email) ORDER BY users.name SEPARATOR '::') AS users")
    editable = Arel.sql("BIT_OR(CASE WHEN users.id=#{current_user.id} OR #{current_user.admin?} THEN 1 ELSE 0 END) AS editable")
    creator = Arel.sql("creators_projects.name AS creator")
    creator_id = Arel.sql("creators_projects.id AS creator_id")
    mngs_runs_count = Arel.sql("COUNT(DISTINCT CASE WHEN samples.initial_workflow='#{WorkflowRun::WORKFLOW[:short_read_mngs]}' THEN samples.id ELSE NULL END) AS mngs_runs_count")
    cg_runs_count = Arel.sql("COUNT(DISTINCT (CASE
                                WHEN workflow_runs.workflow = '#{WorkflowRun::WORKFLOW[:consensus_genome]}' AND workflow_runs.deprecated = false AND workflow_runs.deleted_at IS NULL THEN workflow_runs.id
                                WHEN samples.initial_workflow = '#{WorkflowRun::WORKFLOW[:consensus_genome]}' THEN samples.id
                                ELSE NULL
                              END)
                    ) AS cg_runs_count")
    amr_runs_count = Arel.sql("COUNT(DISTINCT (CASE
                                WHEN workflow_runs.workflow = '#{WorkflowRun::WORKFLOW[:amr]}' AND workflow_runs.deprecated = false AND workflow_runs.deleted_at IS NULL THEN workflow_runs.id
                                WHEN samples.initial_workflow = '#{WorkflowRun::WORKFLOW[:amr]}' THEN samples.id
                                ELSE NULL
                              END)
                      ) AS amr_runs_count")

    attrs = [
      *discovery_project_basic_attributes, group_concat_sample_type, group_concat_host, group_concat_location, editable, group_concat_users, creator, creator_id, mngs_runs_count, cg_runs_count, amr_runs_count,
    ]
    names = attrs.map { |attr| attr.split(" AS ").last }
    name_email = ["name", "email"]
    metadata = ["locations", "hosts", "sample_types"]

    # Parentheses are very important. With do..end map returns nil before it is run (same does not happen with curly braces {} )
    (projects_scope.pluck(*attrs).map do |p|
      project_hash = names.zip(p).to_h

      # Don't show list of project members unless they can edit the project.
      # :: and | are used as separators in the SQL queries above, so split on them here.
      project_hash["users"] = project_hash["editable"] == 1 ? (project_hash["users"] || "").split("::").map { |u| name_email.zip(u.split("|")).to_h } : []
      project_hash["owner"] = project_hash["creator"]

      project_hash["editable"] = current_user.admin? || project_hash["editable"] == 1

      metadata.each { |k| project_hash[k] = (project_hash[k] || "").split("::") }
      # Return as "tissue" for legacy compatibility. It's too hard to
      # rename all JS instances of "tissue".
      project_hash["tissues"] = project_hash["sample_types"]

      project_hash["sample_counts"] = project_hash.slice("number_of_samples", "mngs_runs_count", "cg_runs_count", "amr_runs_count")
      project_hash.except("sample_types", "number_of_samples", "mngs_runs_count", "cg_runs_count", "amr_runs_count")
    end)
  end
end

module Queries
  # Ported from the GraphQL federation server (resolver-functions/fedBulkDownloads) as
  # part of CZID-285 (303c). Serves the bulk-download list natively instead of proxying
  # GET /bulk_downloads.json. Mirrors BulkDownloadsController#index (viewable scope +
  # admin-only searchBy/limit) and BulkDownloadsHelper#format_bulk_download, then applies
  # the federation resolver's mapping (status enum, entityInputs concat, params filter).
  module FedBulkDownloadsQuery
    extend ActiveSupport::Concern
    include BulkDownloadsHelper # format_bulk_download

    # Rails bulk-download status -> the federation's NextGen-style status enum.
    NEXTGEN_STATUSES = {
      "success" => "SUCCEEDED",
      "error" => "FAILED",
      "waiting" => "PENDING",
      "running" => "RUNNING",
    }.freeze

    # params keys that are plumbing, not sidebar-displayable.
    PARAM_KEY_EXCLUSIONS = %w[workflow sample_ids].freeze

    included do
      field :fedBulkDownloads,
            [Types::FedBulkDownloadsType],
            null: true,
            camelize: false,
            resolver_method: :resolve_fed_bulk_downloads do
        argument :input, Types::FedBulkDownloadsInputType, required: false
      end
    end

    def resolve_fed_bulk_downloads(input: nil)
      admin = current_user.admin?
      scope = current_power.viewable_bulk_downloads

      if admin
        if input&.search_by.present?
          user_ids = User.where("name like ? OR email like ?", "%#{input.search_by}%", "%#{input.search_by}%").pluck(:id)
          scope = scope.where(user_id: user_ids)
        end
        scope = scope.order(id: :desc).limit(input.limit) if input&.limit.present?
      end

      scope.includes(:pipeline_runs, :workflow_runs, :user).map do |bulk_download|
        formatted = format_bulk_download(bulk_download, detailed: true, admin: admin).as_json
        map_fed_bulk_download(formatted)
      end
    end

    private

    def map_fed_bulk_download(bulk_download)
      {
        id: bulk_download["id"]&.to_s,
        startedAt: bulk_download["created_at"],
        status: NEXTGEN_STATUSES[bulk_download["status"]],
        downloadType: bulk_download["download_type"],
        ownerUserId: bulk_download["user_id"],
        fileSize: bulk_download["output_file_size"],
        url: bulk_download["presigned_output_url"],
        analysisCount: bulk_download["analysis_count"],
        entityInputFileType: bulk_download["analysis_type"],
        entityInputs: bulk_download_entity_inputs(bulk_download),
        errorMessage: bulk_download["error_message"],
        params: bulk_download_params(bulk_download["params"]),
        logUrl: bulk_download["log_url"],
      }
    end

    def bulk_download_entity_inputs(bulk_download)
      entities = Array(bulk_download["workflow_runs"]) + Array(bulk_download["pipeline_runs"])
      entities.map { |entity| { id: entity["id"]&.to_s, name: entity["sample_name"] } }
    end

    def bulk_download_params(params)
      return [] unless params.is_a?(Hash)

      params.filter_map do |key, param|
        next if PARAM_KEY_EXCLUSIONS.include?(key)
        next if param.nil? || param["value"].nil?

        value = param["value"]
        next if value.is_a?(Array) && value.empty?

        {
          paramType: snake_to_camel(key),
          displayName: param["displayName"],
          value: value.is_a?(String) ? value : value.to_json,
        }
      end
    end

    def snake_to_camel(str)
      str.to_s.gsub(/_([a-zA-Z0-9])/) { Regexp.last_match(1).upcase }
    end
  end
end

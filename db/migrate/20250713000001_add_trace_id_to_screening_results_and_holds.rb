# SMP-1253 (Export-control Layer 3 -- audit trail / diagnostic logging). Adds an OpenTelemetry trace
# correlation id to the screening evidence rows so each DURABLE audit record (the system-of-record)
# cross-links to its distributed trace and to the always-on [screening_audit] structured log line.
# ADDITIVE + nullable -- no existing table data is touched, and nothing writes trace_id until the
# Descartes ScreeningService is enabled behind its OFF-by-default flag (ships dark). Traces are the
# diagnostic/correlation layer only; the audit trail itself stays in these DB rows.
class AddTraceIdToScreeningResultsAndHolds < ActiveRecord::Migration[7.2]
  def change
    # if_not_exists keeps the migration self-healing if a prior run half-applied (same pattern as the
    # CZID-597 create_table migrations).
    add_column :screening_results, :trace_id, :string, if_not_exists: true
    add_column :holds, :trace_id, :string, if_not_exists: true
  end
end

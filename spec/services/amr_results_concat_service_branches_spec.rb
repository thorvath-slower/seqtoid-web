# frozen_string_literal: true

require "rails_helper"

# Coverage Wave 3: branch sweep for AmrResultsConcatService. The main spec runs
# a single workflow run, so the "headers already set on a later run" else and
# the nil parsed_cached_results &.dig arm stay untaken. These add a two-run
# concat (second run skips the header write) and a run with no cached results.
RSpec.describe AmrResultsConcatService, type: :service do
  let(:project) { create(:project) }

  let(:report_content) do
    [
      "gene_name\tnum_reads\tread_coverage_depth",
      "gene_a\t10\t5",
    ].join("\n")
  end

  def build_amr_run(cached: true)
    cached_results = if cached
                       { "quality_metrics" => { "total_reads" => 1_000, "total_ercc_reads" => 0, "fraction_subsampled" => 1.0 } }.to_json
                     end
    run = create(:workflow_run, sample: create(:sample, project: project),
                                workflow: WorkflowRun::WORKFLOW[:amr],
                                cached_results: cached_results)
    run.becomes(AmrWorkflowRun)
  end

  before do
    allow_any_instance_of(AmrWorkflowRun)
      .to receive(:output_path)
      .with(AmrWorkflowRun::OUTPUT_REPORT)
      .and_return("s3://fake-bucket/amr-report.tsv")
    allow(S3Util).to receive(:get_s3_file).and_return(report_content)
  end

  it "writes the header only once when concatenating multiple runs (the headers-already-set else)" do
    run1 = build_amr_run
    run2 = build_amr_run

    csv = AmrResultsConcatService.call([run1.id, run2.id])
    parsed = CSVSafe.parse(csv, headers: true)

    # One header row + one data row per run = 2 data rows, single header set.
    expect(parsed.length).to eq(2)
    expect(parsed.headers).to include("total_reads", "rpm", "dpm")
  end

  it "emits a nil total_reads when a run has no cached quality_metrics (the &.dig nil arm)" do
    run = build_amr_run(cached: false)

    csv = AmrResultsConcatService.call([run.id])
    parsed = CSVSafe.parse(csv, headers: true)

    expect(parsed.length).to eq(1)
    expect(parsed.first["total_reads"].to_s).to be_empty
  end
end

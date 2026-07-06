require "rails_helper"

RSpec.describe AmrResultsConcatService, type: :service do
  let(:sample) { create(:sample, project: create(:project)) }

  # A tab-separated AMR report with a header + two data rows.
  # Columns include num_reads and read_coverage_depth used to compute rpm/dpm.
  let(:report_content) do
    [
      "gene_name\tnum_reads\tread_coverage_depth",
      "gene_a\t10\t5",
      "gene_b\t20\t8",
    ].join("\n")
  end

  def build_amr_run
    run = create(
      :workflow_run,
      sample: sample,
      workflow: WorkflowRun::WORKFLOW[:amr],
      cached_results: { "quality_metrics" => { "total_reads" => 1_000, "total_ercc_reads" => 0, "fraction_subsampled" => 1.0 } }.to_json
    )
    run.becomes(AmrWorkflowRun)
  end

  before do
    # The service resolves the report S3 path via SfnExecution#output_path, which
    # would otherwise reach into a real (absent) SFN description and raise
    # SfnDescriptionNotFoundError. Stub it so tests exercise the concat logic,
    # not the SFN-path resolution.
    allow_any_instance_of(AmrWorkflowRun)
      .to receive(:output_path)
      .with(AmrWorkflowRun::OUTPUT_REPORT)
      .and_return("s3://fake-bucket/amr-report.tsv")
  end

  describe "#call" do
    context "when a workflow run id does not exist" do
      it "raises WorkflowRunNotFoundError with the missing id" do
        expect do
          AmrResultsConcatService.call([-1])
        end.to raise_error(AmrResultsConcatService::WorkflowRunNotFoundError, /-1/)
      end
    end

    context "when the S3 output file is missing" do
      it "raises S3FileNotFound" do
        run = build_amr_run
        allow(S3Util).to receive(:get_s3_file).and_return(nil)

        expect do
          AmrResultsConcatService.call([run.id])
        end.to raise_error(AmrResultsConcatService::S3FileNotFound)
      end
    end

    context "when the report has content" do
      before do
        allow(S3Util).to receive(:get_s3_file).and_return(report_content)
      end

      it "produces a CSV with the original headers plus total_reads, rpm and dpm" do
        run = build_amr_run
        csv = AmrResultsConcatService.call([run.id])
        parsed = CSVSafe.parse(csv, headers: true)

        expect(parsed.headers).to include("gene_name", "num_reads", "read_coverage_depth", "total_reads", "rpm", "dpm")
        expect(parsed.length).to eq(2)
      end

      it "appends per-row rpm/dpm derived from num_reads and read_coverage_depth" do
        run = build_amr_run
        csv = AmrResultsConcatService.call([run.id])
        parsed = CSVSafe.parse(csv, headers: true)
        first_row = parsed.first

        # rpm = num_reads / (total_reads * fraction_subsampled) * 1e6 = 10 / 1000 * 1e6 = 10_000
        expect(first_row["rpm"].to_f).to be_within(0.01).of(10_000.0)
        # dpm = read_coverage_depth / 1000 * 1e6 = 5 / 1000 * 1e6 = 5_000
        expect(first_row["dpm"].to_f).to be_within(0.01).of(5_000.0)
        expect(first_row["total_reads"].to_i).to eq(1_000)
      end
    end

    context "when the report content is empty" do
      it "returns a CSV with no data rows" do
        run = build_amr_run
        allow(S3Util).to receive(:get_s3_file).and_return("")

        csv = AmrResultsConcatService.call([run.id])
        parsed = CSVSafe.parse(csv, headers: true)
        expect(parsed.length).to eq(0)
      end
    end
  end
end

require "rails_helper"

# Coverage Wave 5: the existing mngs_reads_stats_load_service_spec covers the
# legacy illumina path and the nanopore path. This file exercises the NEW host
# filtering stage path (pipeline_version >= 8): compile_illumina_stats_v2 and the
# fastp QC count fetching (fetch_fastp_qc_counts), which the old fixtures don't hit.
RSpec.describe MngsReadsStatsLoadService do
  let(:fake_sample_bucket) { ENV['SAMPLES_BUCKET_NAME'] }
  let(:fake_arn) { "fake-arn" }
  let(:version_prefix) { "short-read-mngs-8" }

  # Counts for the new host-filtering stage. Includes bowtie2_ercc_filtered_out,
  # which triggers the extra fastp QC fetch.
  let(:steps) do
    {
      "fastqs": 10_000,
      "validate_input_out": 10_000,
      "fastp_out": 9000,
      "bowtie2_ercc_filtered_out": 8500,
      "truncated": 9500,
      "hisat2_human_filtered_out": 4000,
      "subsampled_out": 2000,
    }
  end

  # fastp.json filtering_result section consumed by fetch_fastp_qc_counts.
  let(:fastp_json) do
    {
      "filtering_result" => {
        "low_quality_reads" => 100,
        "too_short_reads" => 50,
        "too_long_reads" => 10,
        "low_complexity_reads" => 20,
        "too_many_N_reads" => 5,
      },
    }
  end

  before do
    count_files = steps.map do |k, v|
      ["#{version_prefix}/#{k}.count", { body: { "#{k}": v.to_s }.to_json }]
    end.to_h
    count_files["#{version_prefix}/#{PipelineRun::FASTP_JSON_FILE}"] = { body: fastp_json.to_json }

    @mock_aws_clients = { s3: Aws::S3::Client.new(stub_responses: true) }
    allow(AwsClient).to receive(:[]) { |client| @mock_aws_clients[client] }

    @mock_aws_clients[:s3].stub_responses(
      :list_objects_v2, contents: steps.keys.map do |filename|
        { key: File.join("#{fake_sample_bucket}/#{version_prefix}/", "#{filename}.count") }
      end
    )
    @mock_aws_clients[:s3].stub_responses(
      :get_object, lambda { |context|
        count_files[context.params[:key]] || { body: "{}" }
      }
    )

    # upload_stats_file shells out to s3 via Syscall; no-op it.
    allow(Syscall).to receive(:s3_cp).and_return(true)

    @pipeline_run = create(:pipeline_run,
                           technology: PipelineRun::TECHNOLOGY_INPUT[:illumina],
                           pipeline_execution_strategy: "step_function",
                           s3_output_prefix: fake_sample_bucket,
                           sfn_execution_arn: fake_arn,
                           wdl_version: "8.0",
                           pipeline_version: "8.0")
    # Avoid the assembly-refined-count S3 read in fetch_unmapped_illumina_reads.
    allow_any_instance_of(PipelineRun).to receive(:supports_assembly?).and_return(false)
    @response = MngsReadsStatsLoadService.call(@pipeline_run)
  end

  it "loads total_reads and truncated from the new-stage counts" do
    expect(@pipeline_run.total_reads).to eq(steps[:fastqs])
    expect(@pipeline_run.truncated).to eq(steps[:truncated])
  end

  it "sets adjusted_remaining_reads from subsampled_out" do
    expect(@pipeline_run.adjusted_remaining_reads).to eq(steps[:subsampled_out])
  end

  it "computes the subsample fraction from hisat2_human_filtered_out and subsampled_out" do
    expected = (1.0 * steps[:subsampled_out]) / steps[:hisat2_human_filtered_out]
    expect(@pipeline_run.fraction_subsampled).to be_within(1e-9).of(expected)
  end

  it "loads the fastp QC derived counts into job stats" do
    tasks = @pipeline_run.job_stats.pluck(:task)
    expect(tasks).to include("fastp_low_quality_reads", "fastp_too_short_reads", "fastp_low_complexity_reads")
  end

  it "derives fastp_low_quality_reads from bowtie2_ercc_filtered_out minus low_quality_reads" do
    stat = @pipeline_run.job_stats.find_by(task: "fastp_low_quality_reads")
    expect(stat.reads_after).to eq(steps[:bowtie2_ercc_filtered_out] - fastp_json["filtering_result"]["low_quality_reads"])
  end
end

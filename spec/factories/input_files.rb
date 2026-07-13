# InputFile#name and #source MUST stay in lockstep for a given record.
# The SFN dispatch services build S3 paths from `name` (InputFile#s3_path ->
# File.join(sample.sample_input_s3_path, name)), while the dispatch specs derive
# their expectations from `source`. Previously `name` and `source` were TWO
# independent inline sequences; any spec that overrode only one of them (e.g.
# create(:local_web_reference_sequence_input_file, name: "ref.fasta")) desynced
# the two global counters, so every subsequent fastq record had name == "file.K"
# but source == "file.K+1". The dispatch specs then asserted `source` against a
# service output built from `name` and failed off-by-N once suite composition
# changed. Deriving `source` from `name` makes them identical by construction, so
# overriding `name` also moves `source` and they can never skew. (CZID-294)
FactoryBot.define do
  factory :local_web_input_file, class: InputFile do
    sequence(:name) { |n| "file.#{n}.fastq.gz" }
    source { name }
    source_type { "local" }
    upload_client { "web" }
    file_type { InputFile::FILE_TYPE_FASTQ }
  end

  factory :local_web_reference_sequence_input_file, class: InputFile do
    name { "file.fasta.gz" }
    source { name }
    source_type { "local" }
    upload_client { "web" }
    file_type { InputFile::FILE_TYPE_REFERENCE_SEQUENCE }
  end

  factory :local_web_primer_bed_input_file, class: InputFile do
    name { "file.bed.gz" }
    source { name }
    source_type { "local" }
    upload_client { "web" }
    file_type { InputFile::FILE_TYPE_PRIMER_BED }
  end
end

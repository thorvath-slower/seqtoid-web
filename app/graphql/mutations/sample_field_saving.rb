module Mutations
  # Shared by the UpdateSampleName / UpdateSampleNotes mutations (CZID-304). Mirrors
  # SamplesController#save_metadata exactly: only the allowed sample fields (name /
  # sample_notes) are writable; a blank-over-blank write is ignored; the {status, message}
  # contract matches the REST action (and the federation, which proxied it).
  module SampleFieldSaving
    def save_sample_field(sample, field, value)
      field = field.to_sym
      metadata = { field => value }
      metadata.select! { |k, _v| (Sample::METADATA_FIELDS + [:name]).include?(k) }

      if sample[field].blank? && value.to_s.strip.blank?
        { status: "ignored", message: nil }
      else
        sample.update!(metadata)
        { status: "success", message: "Saved successfully" }
      end
    rescue StandardError
      { status: "failed", message: "Unable to update sample" }
    end
  end
end

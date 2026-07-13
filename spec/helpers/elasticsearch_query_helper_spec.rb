require "rails_helper"
require "webmock/rspec"

RSpec.describe ElasticsearchQueryHelper, type: :helper do
  describe "#build_categories_filter_clause" do
    it "should return valid categories if phage is true and categories are blank " do
      categories_clause = ElasticsearchQueryHelper.build_categories_filter_clause([], true)
      expect(categories_clause[0].keys[0].to_s).to eq "term"
      expect(categories_clause[0][:term].keys[0].to_s).to eq "superkingdom_taxid"
      expect(categories_clause[0][:term][:superkingdom_taxid]).to eq "10239"
      expect(categories_clause[1][:term][:is_phage]).to eq 1
    end

    it "should return valid categories for Bacteria" do
      categories_clause = ElasticsearchQueryHelper.build_categories_filter_clause(["Bacteria"], false)
      expect(categories_clause[0].keys[0].to_s).to eq "terms"
      expect(categories_clause[0][:terms].keys[0].to_s).to eq "superkingdom_taxid"
      expect(categories_clause[0][:terms][:superkingdom_taxid].size).to eq 1
      expect(categories_clause[0][:terms][:superkingdom_taxid][0]).to eq 2
    end

    it "should return nil if categories is blank and phage is false" do
      categories_clause = ElasticsearchQueryHelper.build_categories_filter_clause([], false)
      expect(categories_clause).to be_empty
    end
  end

  describe "#build_read_specificity_filter_clause" do
    it "should return read specificity clause if read_specificity is 1" do
      read_specificity_clause = ElasticsearchQueryHelper.build_read_specificity_filter_clause(1)
      expect(read_specificity_clause[0]).to eq({ range: { tax_id: { gte: "0" } } })
    end
    it "should not return read specificity clause if read_specificity is not 1" do
      read_specificity_clause = ElasticsearchQueryHelper.build_read_specificity_filter_clause(0)
      expect(read_specificity_clause[0]).to eq nil
    end
  end

  describe "#call_taxon_indexing_lambda" do
    let(:background_id) { 1 }
    let(:pipeline_run_ids) { [101, 102] }

    def lambda_resp(body)
      OpenStruct.new(payload: OpenStruct.new(string: body))
    end

    it "raises a clear error (not JSON::ParserError) when the lambda returns an empty body" do
      allow(ElasticsearchQueryHelper).to receive(:call_lambda).and_return(lambda_resp(""))
      allow(LogUtil).to receive(:log_error)
      expect do
        ElasticsearchQueryHelper.call_taxon_indexing_lambda(background_id, pipeline_run_ids)
      end.to raise_error(/empty response/)
    end

    it "raises a clear error when the lambda returns an unparseable body" do
      allow(ElasticsearchQueryHelper).to receive(:call_lambda).and_return(lambda_resp("not json"))
      allow(LogUtil).to receive(:log_error)
      expect do
        ElasticsearchQueryHelper.call_taxon_indexing_lambda(background_id, pipeline_run_ids)
      end.to raise_error(/unparseable response/)
    end

    it "raises when the payload is not an array (unexpected shape)" do
      allow(ElasticsearchQueryHelper).to receive(:call_lambda).and_return(lambda_resp('{"error":"boom"}'))
      allow(LogUtil).to receive(:log_error)
      expect do
        ElasticsearchQueryHelper.call_taxon_indexing_lambda(background_id, pipeline_run_ids)
      end.to raise_error(/unexpected response/)
    end

    it "raises when any invocation reports a FunctionError" do
      allow(ElasticsearchQueryHelper).to receive(:call_lambda)
        .and_return(lambda_resp('[{"FunctionError":"Unhandled"},{}]'))
      allow(LogUtil).to receive(:log_error)
      expect do
        ElasticsearchQueryHelper.call_taxon_indexing_lambda(background_id, pipeline_run_ids)
      end.to raise_error(/Some taxon indexing jobs failed/)
    end

    it "succeeds when all invocations succeed" do
      allow(ElasticsearchQueryHelper).to receive(:call_lambda).and_return(lambda_resp('[{},{}]'))
      expect do
        ElasticsearchQueryHelper.call_taxon_indexing_lambda(background_id, pipeline_run_ids)
      end.not_to raise_error
    end
  end

  describe "#parse_es_response" do
    let(:es_resp) { file_fixture("helpers/elasticsearch_query_helper/es_response.json").read }
    it "should return 2 taxons" do
      taxons = ElasticsearchQueryHelper.parse_es_response(JSON.parse(es_resp))
      expect(taxons.size).to eq 4
      expect(taxons[0].keys.size).to eq 20
      expect(taxons[0].key?("rpm")).to eq true
      expect(taxons[0]["rpm"]).to eq 3.7452
      expect(taxons[1].key?("zscore")).to eq true
      expect(taxons[1]["zscore"]).to eq 99.0
    end
  end

  describe "#parse_custom_filters" do
    it "parses valid filters into count_type/metric/value/operator" do
      parsed = ElasticsearchQueryHelper.parse_custom_filters(
        [{ "metric" => "NT_rpm", "value" => "5", "operator" => ">=" }]
      )
      expect(parsed).to eq([{ count_type: "NT", metric: "rpm", value: 5.0, operator: ">=" }])
    end

    it "skips filters with unparseable values" do
      allow(Rails.logger).to receive(:warn)
      parsed = ElasticsearchQueryHelper.parse_custom_filters(
        [{ "metric" => "NR_zscore", "value" => "not-a-number", "operator" => "<=" }]
      )
      expect(parsed).to be_empty
      expect(Rails.logger).to have_received(:warn)
    end

    it "returns an empty array for no filters" do
      expect(ElasticsearchQueryHelper.parse_custom_filters([])).to eq([])
    end
  end

  describe "#build_nested_threshold_filter_clause" do
    it "returns nil when no filters match the given count_type" do
      clause = ElasticsearchQueryHelper.build_nested_threshold_filter_clause("NT", [])
      expect(clause).to be_nil
    end

    it "builds a nested range clause with gte for >= filters" do
      filters = [{ "metric" => "NT_rpm", "value" => "5", "operator" => ">=" }]
      clause = ElasticsearchQueryHelper.build_nested_threshold_filter_clause("NT", filters)
      nested_filters = clause[:nested][:query][:bool][:filter]
      # first clause always constrains the count_type
      expect(nested_filters[0][:term][:"metric_list.count_type"]).to eq "NT"
      expect(nested_filters[1][:range][:"metric_list.rpm"][:gte]).to eq "5.0"
    end

    it "uses lte for <= filters and maps the metric name" do
      filters = [{ "metric" => "NR_percentidentity", "value" => "80", "operator" => "<=" }]
      clause = ElasticsearchQueryHelper.build_nested_threshold_filter_clause("NR", filters)
      nested_filters = clause[:nested][:query][:bool][:filter]
      expect(nested_filters[1][:range][:"metric_list.percent_identity"][:lte]).to eq "80.0"
    end
  end

  describe "#build_threshold_filters_clause" do
    it "returns an empty array when there are no filters" do
      expect(ElasticsearchQueryHelper.build_threshold_filters_clause([])).to eq([])
    end

    it "returns both an NT and NR clause when both count types are present" do
      filters = [
        { "metric" => "NT_rpm", "value" => "5", "operator" => ">=" },
        { "metric" => "NR_rpm", "value" => "1", "operator" => ">=" },
      ]
      clause = ElasticsearchQueryHelper.build_threshold_filters_clause(filters)
      expect(clause.size).to eq 2
    end
  end

  describe "#change_field_name" do
    it "renames ES fields to their UI aliases" do
      metric = { "counts" => 10, "percent_identity" => 99.5, "e_value" => -12.0, "alignment_length" => 50 }
      result = ElasticsearchQueryHelper.change_field_name(metric)
      expect(result["r"]).to eq 10
      expect(result["percentidentity"]).to eq 99.5
      expect(result["logevalue"]).to eq(-12.0)
      expect(result["alignmentlength"]).to eq 50
      expect(result).not_to have_key("counts")
    end
  end

  describe "#round_decimal_value" do
    it "rounds rpm/zscore/r to 4 decimal places as floats" do
      metric = { "rpm" => 3.745219, "zscore" => 2.0, "r" => 7 }
      result = ElasticsearchQueryHelper.round_decimal_value(metric)
      expect(result["rpm"]).to eq 3.7452
      expect(result["zscore"]).to eq 2.0
      expect(result["r"]).to eq 7.0
    end

    it "leaves nil values as nil" do
      metric = { "rpm" => nil, "zscore" => nil, "r" => nil }
      result = ElasticsearchQueryHelper.round_decimal_value(metric)
      expect(result["rpm"]).to be_nil
      expect(result["zscore"]).to be_nil
      expect(result["r"]).to be_nil
    end
  end

  describe "#parse_top_n_taxa_per_sample_response" do
    it "flattens aggregation buckets into a unique list of tax_ids" do
      response = {
        "aggregations" => {
          "pipeline_runs" => {
            "buckets" => [
              { "top_taxa" => { "hits" => { "hits" => [
                { "_source" => { "tax_id" => 1 } },
                { "_source" => { "tax_id" => 2 } },
              ] } } },
              { "top_taxa" => { "hits" => { "hits" => [
                { "_source" => { "tax_id" => 2 } },
                { "_source" => { "tax_id" => 3 } },
              ] } } },
            ],
          },
        },
      }
      expect(ElasticsearchQueryHelper.parse_top_n_taxa_per_sample_response(response)).to eq([1, 2, 3])
    end
  end

  describe "#compute_aggregate_scores_v2!" do
    it "sets NT and NR maxzscore to the max of the two zscores" do
      rows = [{ "NT" => { "zscore" => 3.0 }, "NR" => { "zscore" => 5.0 } }]
      ElasticsearchQueryHelper.compute_aggregate_scores_v2!(rows)
      expect(rows[0]["NT"]["maxzscore"]).to eq 5.0
      expect(rows[0]["NR"]["maxzscore"]).to eq 5.0
    end
  end

  describe "#batch_tax_ids" do
    it "returns a single batch when the product is within the ES page limit" do
      expect(ElasticsearchQueryHelper.batch_tax_ids([1, 2], [10, 20, 30])).to eq([[10, 20, 30]])
    end

    it "raises when there are too many pipeline runs" do
      expect do
        ElasticsearchQueryHelper.batch_tax_ids(Array.new(10_001, 1), [1])
      end.to raise_error(/too many samples/)
    end

    it "splits tax_ids into multiple batches when the product exceeds the limit" do
      pipeline_run_ids = Array.new(200, 1)
      tax_ids = (1..100).to_a
      batches = ElasticsearchQueryHelper.batch_tax_ids(pipeline_run_ids, tax_ids)
      expect(batches.size).to be > 1
      expect(batches.flatten).to match_array(tax_ids)
    end
  end

  describe "#build_taxon_tags_filter_clause" do
    it "returns an empty array when known_pathogens is not requested" do
      expect(ElasticsearchQueryHelper.build_taxon_tags_filter_clause([])).to eq([])
      expect(ElasticsearchQueryHelper.build_taxon_tags_filter_clause(nil)).to eq([])
    end
  end

  describe "#paginate_all_results" do
    it "raises when the search body has no sort parameter" do
      expect do
        ElasticsearchQueryHelper.paginate_all_results("some_index", {})
      end.to raise_error(/must include a sort parameter/)
    end

    it "recurses over pages until an empty page is returned" do
      client = double("es_client")
      stub_const("ElasticsearchQueryHelper::ES_CLIENT", client)

      page1 = { "hits" => { "hits" => [{ "_source" => { "tax_id" => 1 }, "sort" => [1] }] } }
      page2 = { "hits" => { "hits" => [] } }
      allow(client).to receive(:search).and_return(page1, page2)

      results = ElasticsearchQueryHelper.paginate_all_results("idx", { sort: [{ "tax_id" => { "order" => "asc" } }] })
      expect(results.size).to eq 1
      expect(results.first["_source"]["tax_id"]).to eq 1
    end
  end

  describe "#find_complete_pipeline_runs" do
    it "returns the pipeline_run_ids reported complete by ES" do
      client = double("es_client")
      stub_const("ElasticsearchQueryHelper::ES_CLIENT", client)
      allow(client).to receive(:search).and_return(
        { "hits" => { "hits" => [
          { "_source" => { "pipeline_run_id" => 101 } },
          { "_source" => { "pipeline_run_id" => 102 } },
        ] } }
      )
      expect(ElasticsearchQueryHelper.find_complete_pipeline_runs(1, [101, 102, 103])).to eq([101, 102])
    end
  end

  describe "#find_pipeline_runs_missing_from_es" do
    it "returns an empty array when no pipeline_run_ids are given" do
      expect(ElasticsearchQueryHelper.find_pipeline_runs_missing_from_es(1, [])).to eq([])
    end

    it "returns the pipeline_run_ids not present in ES" do
      allow(ElasticsearchQueryHelper).to receive(:find_complete_pipeline_runs).and_return([101])
      expect(ElasticsearchQueryHelper.find_pipeline_runs_missing_from_es(1, [101, 102, 103])).to eq([102, 103])
    end
  end

  describe "#fetch_all_metrics_per_sample_and_taxa" do
    it "builds the query and shapes the ES response via parse_es_response" do
      es_resp = JSON.parse(file_fixture("helpers/elasticsearch_query_helper/es_response.json").read)
      client = double("es_client")
      stub_const("ElasticsearchQueryHelper::ES_CLIENT", client)
      expect(client).to receive(:search).with(
        hash_including(index: "scored_taxon_counts")
      ).and_return(es_resp)

      results = ElasticsearchQueryHelper.fetch_all_metrics_per_sample_and_taxa([28_321], [84_023], 26)
      expect(results).to be_an(Array)
      expect(results.first).to have_key("rpm")
    end
  end
end

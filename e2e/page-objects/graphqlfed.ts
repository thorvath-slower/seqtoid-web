import { PageObject } from "./page-object";
const LIMIT = 100000;

/**
 * Page object for querying the Rails-native GraphQL endpoint (`/graphql`) from e2e tests.
 *
 * The class is still named `Graphqlfed` for history: before CZID-285 it targeted the GraphQL
 * federation server (`/graphqlfed`). CZID-305 cut the app's Relay client over to Rails `/graphql`
 * and CZID-306 decommissioned the federation, so this now POSTs to `/graphql`. The name is kept
 * so existing importers don't break (no-rename); new code can use the `RailsGraphql` alias below.
 */
export class Graphqlfed extends PageObject {
  /**
   * POST a GraphQL operation to the Rails-native endpoint.
   *
   * Rails `GraphqlController` uses `protect_from_forgery with: :null_session`, so the request must
   * carry BOTH the session cookie (shared automatically via `page.context().request`) AND the
   * Rails CSRF token — read here from the authenticated page's `csrf-token` meta tag — or
   * `current_user` is nullified and the query runs unauthenticated. Mirrors
   * `app/assets/src/relay/environment.ts` (`getCsrfToken()` + `X-CSRF-Token`).
   */
  private async postGraphql(query: string, variables: Record<string, unknown>) {
    const csrfToken =
      (await this.page.getAttribute('meta[name="csrf-token"]', "content")) ?? "";
    const response = await this.page
      .context()
      .request.post(`${process.env.BASEURL}/graphql`, {
        headers: { "X-CSRF-Token": csrfToken },
        data: { query, variables },
      });
    return response.json();
  }

  public async projectSamplesByTaxon(project: any, taxon: any) {
    const responseJson = await this.postGraphql(
      `query MyQuery($taxonName: [String], $limit: Int) {
        fedSequencingReads(
          input: {limit: $limit, where: {taxon: {name: {_in: $taxonName}}}}
        ) {
          id
          sample {
            collection {
              name
            }
            name
          }
          taxon {
            name
          }
        }
      }`,
      { taxonName: taxon.title, limit: LIMIT },
    );
    let filteredSequencingReads = responseJson.data.fedSequencingReads.filter(
      r => r.sample.collection.name === project.name,
    );
    filteredSequencingReads = responseJson.data.fedSequencingReads.filter(
      r => r.taxon && r.taxon.name.includes(taxon.title),
    );
    return filteredSequencingReads.map(r => r.sample.name);
  }

  public async projectSamplesByCollectionLocation(
    project: any,
    collectionLocation: string,
  ) {
    const responseJson = await this.postGraphql(
      `query MyQuery($collectionLocation: [String], $limit: Int) {
        fedSequencingReads(
          input: {limit: $limit, where: {sample: {collectionLocation: {_in: $collectionLocation}}}}
        ) {
          sample {
            name
            collectionLocation
            collection {
              name
            }
          }
          taxon {
            name
          }
        }
      }`,
      { collectionLocation: collectionLocation, limit: LIMIT },
    );
    const filteredSequencingReads = responseJson.data.fedSequencingReads.filter(
      r =>
        r.sample.collection.name === project.name &&
        r.sample.collectionLocation === collectionLocation,
    );
    return filteredSequencingReads.map(r => r.sample.name);
  }

  public async projectSamplesByHostOrganism(
    project: any,
    hostOrganism: string,
  ) {
    const responseJson = await this.postGraphql(
      `query MyQuery($hostOrganism: [String], $limit: Int) {
        fedSequencingReads(
          input: {limit: $limit, where: {sample: {hostOrganism: {name: {_in: $hostOrganism}}}}}
        ) {
          sample {
            name
            collectionLocation
            collection {
              name
              public
            }
            hostOrganism {
              name
            }
          }
          taxon {
            name
          }
        }
      }`,
      { hostOrganism: hostOrganism, limit: LIMIT },
    );
    const filteredSequencingReads = responseJson.data.fedSequencingReads.filter(
      r =>
        r.sample.collection.name === project.name &&
        r.sample.hostOrganism.name === hostOrganism,
    );
    return filteredSequencingReads.map(r => r.sample.name);
  }

  public async projectSamplesSampleType(
    project: any,
    sampleTissueType: string,
  ) {
    const responseJson = await this.postGraphql(
      `query MyQuery($sampleType: [String], $limit: Int) {
        fedSequencingReads(
          input: {where: {sample: {sampleType: {_in: $sampleType}}}, limit: $limit}
        ) {
          taxon {
            name
          }
          sample {
            name
            collectionLocation
            collection {
              name
              public
            }
            sampleType
          }
        }
      }`,
      { sampleType: sampleTissueType, limit: LIMIT },
    );
    const filteredSequencingReads = responseJson.data.fedSequencingReads.filter(
      r =>
        r.sample.collection.name === project.name &&
        r.sample.sampleType === sampleTissueType,
    );
    return filteredSequencingReads.map(r => r.sample.name);
  }

  public async sampleViewSampleQuery(sampleId: string) {
    const responseJson = await this.postGraphql(
      `query SampleViewSampleQuery(
        $railsSampleId: String
          $snapshotLinkId: String
          ) {
            SampleForReport(railsSampleId: $railsSampleId, snapshotLinkId: $snapshotLinkId) {
              id
              created_at
              default_background_id
              default_pipeline_run_id
              editable
              host_genome_id
              initial_workflow
              name
              pipeline_runs {
                adjusted_remaining_reads
                alignment_config_name
                assembled
                created_at
                id
                pipeline_version
                run_finalized
                total_ercc_reads
                wdl_version
              }
              project {
                id
                name
                pinned_alignment_config
              }
              project_id
              railsSampleId
              status
              updated_at
              upload_error
              user_id
              workflow_runs {
                deprecated
                executed_at
                id
                input_error {
                  label
                  message
                }
                inputs {
                  accession_id
                  accession_name
                  creation_source
                  ref_fasta
                  taxon_id
                  taxon_name
                  technology
                  card_version
                  wildcard_version
                }
                parsed_cached_results {
                  quality_metrics {
                    total_reads
                    total_ercc_reads
                    adjusted_remaining_reads
                    percent_remaining
                    qc_percent
                    compression_ratio
                    insert_size_mean
                    insert_size_standard_deviation
                  }
                }
                run_finalized
                status
                wdl_version
                workflow
              }
            }
          }`,
      { railsSampleId: sampleId, snapshotLinkId: "" },
    );
    return responseJson.data.SampleForReport;
  }
}

// Correctly-named alias for new code; `Graphqlfed` is retained for existing importers (no-rename).
export const RailsGraphql = Graphqlfed;

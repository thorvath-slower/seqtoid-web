// CZID-462 (#586) coverage: request-shaping for the thin api transport wrappers.
// The core transport (get/postWithCSRF/putWithCSRF/deleteWithCSRF) is mocked so
// each test asserts the URL + params each endpoint builds.
import * as core from "../app/assets/src/api/core";

jest.mock("../app/assets/src/api/core", () => ({
  get: jest.fn(() => Promise.resolve("GET_RESULT")),
  postWithCSRF: jest.fn(() => Promise.resolve("POST_RESULT")),
  putWithCSRF: jest.fn(() => Promise.resolve("PUT_RESULT")),
  deleteWithCSRF: jest.fn(() => Promise.resolve("DELETE_RESULT")),
}));

import {
  validateSampleIds,
  validateWorkflowRunIds,
} from "../app/assets/src/api/access_control";
import {
  getAMRCounts,
  getAmrDeprecatedData,
  getOntology,
} from "../app/assets/src/api/amr";
import {
  getBasespaceProjects,
  getSamplesForBasespaceProject,
} from "../app/assets/src/api/basespace";
import {
  createAnnotation,
  fetchLongestContigsForTaxonId,
  fetchLongestReadsForTaxonId,
} from "../app/assets/src/api/blast";
import {
  createBulkDownload,
  createSampleMetadataBulkDownload,
  getBulkDownloadMetrics,
  getBulkDownloadTypes,
} from "../app/assets/src/api/bulk_downloads";
import { getGeoSearchSuggestions } from "../app/assets/src/api/locations";
import {
  createPersistedBackground,
  getPersistedBackground,
  updatePersistedBackground,
} from "../app/assets/src/api/persisted_backgrounds";
import {
  chooseTaxon,
  getPhyloTreeNg,
  rerunPhyloTreeNg,
} from "../app/assets/src/api/phylo_tree_ngs";
import { getGraph } from "../app/assets/src/api/pipelineViz";
import {
  createSnapshot,
  deleteSnapshot,
  getSnapshotInfo,
  updateSnapshotBackground,
} from "../app/assets/src/api/snapshot_links";
import { createSupportRequest } from "../app/assets/src/api/support";
import { updateHeatmapName } from "../app/assets/src/api/visualization";
import {
  WORKFLOW_ENTITIES,
  WorkflowType,
} from "../app/assets/src/components/utils/workflows";

const mockGet = core.get as jest.Mock;
const mockPost = core.postWithCSRF as jest.Mock;
const mockPut = core.putWithCSRF as jest.Mock;
const mockDelete = core.deleteWithCSRF as jest.Mock;

beforeEach(() => jest.clearAllMocks());

describe("api/access_control.ts", () => {
  it("validateSampleIds posts sampleIds and workflow", () => {
    validateSampleIds({ sampleIds: [1, 2], workflow: "amr" });
    expect(mockPost).toHaveBeenCalledWith("/samples/validate_sample_ids", {
      sampleIds: [1, 2],
      workflow: "amr",
    });
  });
  it("validateWorkflowRunIds posts workflowRunIds and workflow", () => {
    validateWorkflowRunIds({ workflowRunIds: [3], workflow: "cg" });
    expect(mockPost).toHaveBeenCalledWith(
      "/workflow_runs/validate_workflow_run_ids",
      { workflowRunIds: [3], workflow: "cg" },
    );
  });
});

describe("api/amr.ts", () => {
  it("getAMRCounts gets with sampleIds param", () => {
    getAMRCounts([1, 2]);
    expect(mockGet).toHaveBeenCalledWith("amr_heatmap/amr_counts.json", {
      params: { sampleIds: [1, 2] },
    });
  });
  it("getOntology gets with geneName param", () => {
    getOntology("mecA");
    expect(mockGet).toHaveBeenCalledWith("/amr_ontology/fetch_ontology.json", {
      params: { geneName: "mecA" },
    });
  });
  it("getAmrDeprecatedData gets the sample amr endpoint", () => {
    getAmrDeprecatedData(7);
    expect(mockGet).toHaveBeenCalledWith("/samples/7/amr.json");
  });
});

describe("api/basespace.ts", () => {
  it("getBasespaceProjects passes the access token", () => {
    getBasespaceProjects("tok");
    expect(mockGet).toHaveBeenCalledWith("/basespace/projects", {
      params: { access_token: "tok" },
    });
  });
  it("getSamplesForBasespaceProject passes token and project id", () => {
    getSamplesForBasespaceProject("tok", 99);
    expect(mockGet).toHaveBeenCalledWith("/basespace/samples_for_project", {
      params: { access_token: "tok", basespace_project_id: 99 },
    });
  });
});

describe("api/blast.ts", () => {
  it("fetchLongestContigsForTaxonId defaults countType to NT", () => {
    fetchLongestContigsForTaxonId({
      sampleId: 5,
      pipelineVersion: "6.0",
      taxonId: 100,
    });
    expect(mockGet).toHaveBeenCalledWith(
      "/samples/5/taxid_contigs_for_blast.json",
      { params: { taxid: 100, pipeline_version: "6.0", count_type: "NT" } },
    );
  });
  it("fetchLongestReadsForTaxonId includes tax_level and honors countType", () => {
    fetchLongestReadsForTaxonId({
      countType: "NR",
      sampleId: 5,
      pipelineVersion: "6.0",
      taxonId: 100,
      taxonLevel: 1,
    });
    expect(mockGet).toHaveBeenCalledWith(
      "/samples/5/taxon_five_longest_reads.json",
      {
        params: {
          taxid: 100,
          tax_level: 1,
          pipeline_version: "6.0",
          count_type: "NR",
        },
      },
    );
  });
  it("createAnnotation posts the annotation payload", () => {
    createAnnotation({
      pipelineRunId: 1,
      taxId: 2,
      annotationType: "hit",
    });
    expect(mockPost).toHaveBeenCalledWith("/annotations.json", {
      pipeline_run_id: 1,
      tax_id: 2,
      content: "hit",
    });
  });
});

describe("api/bulk_downloads.ts", () => {
  it("getBulkDownloadTypes builds the workflow query string", () => {
    getBulkDownloadTypes(WorkflowType.SHORT_READ_MNGS);
    expect(mockGet).toHaveBeenCalledWith(
      "/bulk_downloads/types?workflow=short-read-mngs",
    );
  });
  it("getBulkDownloadMetrics builds the workflow query string", () => {
    getBulkDownloadMetrics("amr");
    expect(mockGet).toHaveBeenCalledWith(
      "/bulk_downloads/metrics?workflow=amr",
    );
  });
  it("createBulkDownload maps sample_ids for SAMPLES entity", () => {
    createBulkDownload({
      downloadType: "reads",
      workflowEntity: WORKFLOW_ENTITIES.SAMPLES,
      validObjectIds: [1, 2],
      workflow: "short-read-mngs",
      fields: { foo: "bar" },
    });
    expect(mockPost).toHaveBeenCalledWith("/bulk_downloads", {
      download_type: "reads",
      sample_ids: [1, 2],
      workflow: "short-read-mngs",
      params: {
        sample_ids: { value: [1, 2] },
        workflow: { value: "short-read-mngs" },
        foo: "bar",
      },
    });
  });
  it("createBulkDownload maps workflow_run_ids for non-SAMPLES entity", () => {
    createBulkDownload({
      downloadType: "consensus",
      workflowEntity: WORKFLOW_ENTITIES.WORKFLOW_RUNS,
      validObjectIds: [9],
      workflow: "consensus-genome",
      fields: {},
    });
    expect(mockPost).toHaveBeenCalledWith(
      "/bulk_downloads",
      expect.objectContaining({ workflow_run_ids: [9] }),
    );
  });
  it("createSampleMetadataBulkDownload posts sample_ids", () => {
    createSampleMetadataBulkDownload(["a", "b"]);
    expect(mockPost).toHaveBeenCalledWith("/bulk_downloads/sample_metadata", {
      sample_ids: ["a", "b"],
    });
  });
});

describe("api/locations.ts", () => {
  it("getGeoSearchSuggestions defaults limit to null", () => {
    getGeoSearchSuggestions("san");
    expect(mockGet).toHaveBeenCalledWith("/locations/external_search", {
      params: { query: "san", limit: null },
    });
  });
});

describe("api/persisted_backgrounds.ts", () => {
  it("getPersistedBackground gets by project id", () => {
    getPersistedBackground(3);
    expect(mockGet).toHaveBeenCalledWith("/persisted_backgrounds/3.json");
  });
  it("updatePersistedBackground puts the background id", () => {
    updatePersistedBackground({ projectId: 3, backgroundId: 7 });
    expect(mockPut).toHaveBeenCalledWith("/persisted_backgrounds/3.json", {
      backgroundId: 7,
    });
  });
  it("createPersistedBackground posts project and background ids", () => {
    createPersistedBackground({ projectId: 3, backgroundId: 7 });
    expect(mockPost).toHaveBeenCalledWith("/persisted_backgrounds.json", {
      projectId: 3,
      backgroundId: 7,
    });
  });
});

describe("api/phylo_tree_ngs.ts", () => {
  it("rerunPhyloTreeNg puts the rerun endpoint", () => {
    rerunPhyloTreeNg(4);
    expect(mockPut).toHaveBeenCalledWith("/phylo_tree_ngs/4/rerun");
  });
  it("getPhyloTreeNg gets the tree json", () => {
    getPhyloTreeNg(4);
    expect(mockGet).toHaveBeenCalledWith("/phylo_tree_ngs/4.json");
  });
  it("chooseTaxon gets with query args", () => {
    chooseTaxon({ query: "cov", projectId: 8 });
    expect(mockGet).toHaveBeenCalledWith("/phylo_tree_ngs/choose_taxon", {
      params: { query: "cov", projectId: 8, args: "species,genus" },
    });
  });
});

describe("api/pipelineViz.ts", () => {
  it("getGraph includes the pipeline version when provided", () => {
    getGraph(2, "8.0");
    expect(mockGet).toHaveBeenCalledWith("/samples/2/pipeline_viz/8.0.json");
  });
  it("getGraph omits the version segment when absent", () => {
    getGraph(2, null);
    expect(mockGet).toHaveBeenCalledWith("/samples/2/pipeline_viz.json");
  });
});

describe("api/snapshot_links.ts", () => {
  it("createSnapshot posts the project create endpoint", () => {
    createSnapshot(11);
    expect(mockPost).toHaveBeenCalledWith("/pub/projects/11/create");
  });
  it("getSnapshotInfo gets the info json", () => {
    getSnapshotInfo(11);
    expect(mockGet).toHaveBeenCalledWith("/pub/projects/11/info.json");
  });
  it("deleteSnapshot deletes by share id", () => {
    deleteSnapshot("share-xyz");
    expect(mockDelete).toHaveBeenCalledWith("/pub/share-xyz/destroy");
  });
  it("updateSnapshotBackground puts the background id", () => {
    updateSnapshotBackground("share-xyz", 5);
    expect(mockPut).toHaveBeenCalledWith("/pub/share-xyz/update_background", {
      background_id: 5,
    });
  });
});

describe("api/support.ts", () => {
  it("createSupportRequest posts the snake-cased support payload", () => {
    createSupportRequest({
      description: "help",
      quickReport: { a: 1 } as any,
      diagnostics: { b: 2 } as any,
    });
    expect(mockPost).toHaveBeenCalledWith("/support_requests", {
      description: "help",
      quick_report: { a: 1 },
      diagnostics: { b: 2 },
    });
  });
});

describe("api/visualization.ts", () => {
  it("updateHeatmapName puts the new name", () => {
    updateHeatmapName(21, "My Heatmap");
    expect(mockPut).toHaveBeenCalledWith("/visualizations/21.json", {
      name: "My Heatmap",
    });
  });
});

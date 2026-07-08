// #586 (epic #462) coverage: api/core.ts is the shared HTTP transport. Every verb
// injects a CSRF token (except GET), unwraps resp.data on success, and rejects with
// e.response.data on failure. Mocks axios + the CSRF token source to pin request
// shaping and both success/error arms.
import axios from "axios";
import {
  deleteWithCSRF,
  get,
  MAX_SAMPLES_FOR_GET_REQUEST,
  postWithCSRF,
  putWithCSRF,
} from "../app/assets/src/api/core";

jest.mock("axios");
jest.mock("../app/assets/src/api/utils", () => ({
  getCsrfToken: () => "test-csrf-token",
}));

const mockedAxios = axios as jest.Mocked<typeof axios>;

describe("api/core transport", () => {
  beforeEach(() => jest.clearAllMocks());

  it("exposes the GET request sample cap constant", () => {
    expect(MAX_SAMPLES_FOR_GET_REQUEST).toBe(256);
  });

  describe("get", () => {
    it("returns resp.data and forwards the config", async () => {
      mockedAxios.get.mockResolvedValue({ data: { ok: true } });
      const config = { params: { a: 1 } };
      await expect(get("/url", config)).resolves.toEqual({ ok: true });
      expect(mockedAxios.get).toHaveBeenCalledWith("/url", config);
    });

    it("rejects with e.response.data on failure", async () => {
      mockedAxios.get.mockRejectedValue({ response: { data: "boom" } });
      await expect(get("/url")).rejects.toBe("boom");
    });
  });

  describe("postWithCSRF", () => {
    it("injects the CSRF token into params and returns data", async () => {
      mockedAxios.post.mockResolvedValue({ data: "created" });
      await expect(postWithCSRF("/url", { name: "x" })).resolves.toBe(
        "created",
      );
      expect(mockedAxios.post).toHaveBeenCalledWith("/url", {
        name: "x",
        authenticity_token: "test-csrf-token",
      });
    });

    it("rejects with e.response.data on failure", async () => {
      mockedAxios.post.mockRejectedValue({ response: { data: "bad" } });
      await expect(postWithCSRF("/url")).rejects.toBe("bad");
    });
  });

  describe("putWithCSRF", () => {
    it("injects the CSRF token and returns data", async () => {
      mockedAxios.put.mockResolvedValue({ data: "updated" });
      await expect(putWithCSRF("/url", { id: 1 })).resolves.toBe("updated");
      expect(mockedAxios.put).toHaveBeenCalledWith("/url", {
        id: 1,
        authenticity_token: "test-csrf-token",
      });
    });

    it("rejects with e.response.data on failure", async () => {
      mockedAxios.put.mockRejectedValue({ response: { data: "nope" } });
      await expect(putWithCSRF("/url")).rejects.toBe("nope");
    });
  });

  describe("deleteWithCSRF", () => {
    it("sends the CSRF token in the data body and returns data", async () => {
      mockedAxios.delete.mockResolvedValue({ data: "deleted" });
      await expect(deleteWithCSRF("/url")).resolves.toBe("deleted");
      expect(mockedAxios.delete).toHaveBeenCalledWith("/url", {
        data: { authenticity_token: "test-csrf-token" },
      });
    });

    it("rejects with e.response.data on failure", async () => {
      mockedAxios.delete.mockRejectedValue({ response: { data: "fail" } });
      await expect(deleteWithCSRF("/url")).rejects.toBe("fail");
    });
  });
});

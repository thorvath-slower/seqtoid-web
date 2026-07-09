// CZID-462 (#586) coverage: app/assets/src/api/core.ts and app/assets/src/api/utils.ts
import axios from "axios";
import {
  deleteWithCSRF,
  get,
  MAX_SAMPLES_FOR_GET_REQUEST,
  postWithCSRF,
  putWithCSRF,
} from "../app/assets/src/api/core";
import { getCsrfToken } from "../app/assets/src/api/utils";

jest.mock("axios");
const mockedAxios = axios as jest.Mocked<typeof axios>;

// core.ts reads the CSRF token off the DOM via a <meta name="csrf-token">.
const setCsrfToken = (token: string) => {
  document.head.innerHTML = `<meta name="csrf-token" content="${token}">`;
};

describe("api/utils.ts getCsrfToken", () => {
  it("reads the token content from the DOM", () => {
    setCsrfToken("tok-123");
    expect(getCsrfToken()).toBe("tok-123");
  });
});

describe("api/core.ts", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    setCsrfToken("csrf-abc");
  });

  describe("postWithCSRF", () => {
    it("posts params plus the CSRF token and returns data", async () => {
      mockedAxios.post.mockResolvedValueOnce({ data: { ok: true } });
      const result = await postWithCSRF("/foo", { a: 1 });
      expect(mockedAxios.post).toHaveBeenCalledWith("/foo", {
        a: 1,
        authenticity_token: "csrf-abc",
      });
      expect(result).toEqual({ ok: true });
    });
    it("rejects with the response data on error", async () => {
      mockedAxios.post.mockRejectedValueOnce({ response: { data: "bad" } });
      await expect(postWithCSRF("/foo")).rejects.toBe("bad");
    });
  });

  describe("putWithCSRF", () => {
    it("puts params plus the CSRF token and returns data", async () => {
      mockedAxios.put.mockResolvedValueOnce({ data: { updated: 1 } });
      const result = await putWithCSRF("/bar", { b: 2 });
      expect(mockedAxios.put).toHaveBeenCalledWith("/bar", {
        b: 2,
        authenticity_token: "csrf-abc",
      });
      expect(result).toEqual({ updated: 1 });
    });
    it("rejects with the response data on error", async () => {
      mockedAxios.put.mockRejectedValueOnce({ response: { data: "err" } });
      await expect(putWithCSRF("/bar")).rejects.toBe("err");
    });
  });

  describe("get", () => {
    it("passes through the config and returns data", async () => {
      mockedAxios.get.mockResolvedValueOnce({ data: [1, 2, 3] });
      const config = { params: { q: "x" } };
      const result = await get("/baz", config);
      expect(mockedAxios.get).toHaveBeenCalledWith("/baz", config);
      expect(result).toEqual([1, 2, 3]);
    });
    it("rejects with the response data on error", async () => {
      mockedAxios.get.mockRejectedValueOnce({ response: { data: "nope" } });
      await expect(get("/baz")).rejects.toBe("nope");
    });
  });

  describe("deleteWithCSRF", () => {
    it("sends the CSRF token in the request body and returns data", async () => {
      mockedAxios.delete.mockResolvedValueOnce({ data: { deleted: true } });
      const result = await deleteWithCSRF("/qux");
      expect(mockedAxios.delete).toHaveBeenCalledWith("/qux", {
        data: { authenticity_token: "csrf-abc" },
      });
      expect(result).toEqual({ deleted: true });
    });
    it("rejects with the response data on error", async () => {
      mockedAxios.delete.mockRejectedValueOnce({ response: { data: "fail" } });
      await expect(deleteWithCSRF("/qux")).rejects.toBe("fail");
    });
  });

  it("exposes the max-samples GET constant", () => {
    expect(MAX_SAMPLES_FOR_GET_REQUEST).toBe(256);
  });
});

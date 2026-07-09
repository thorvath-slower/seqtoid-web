const path = require("path");
const webpackConfig = require("./webpack.config.common");

const rootFolder = __dirname;

// Read aliases from webpack configuration and convert to a format that jest understands
const mappedModuleAliases = Object.entries(webpackConfig.resolve.alias)
  .map(([key, value]) => [`^${key}/(.*)$`, `${value}/$1`])
  .reduce((acc, [key, value]) => {
    acc[key] = value;
    return acc;
  }, {});

// This is needed, otherwise Jest gives an error when it tries importing css/scss files.
mappedModuleAliases["\\.(css|scss)$"] = "jest/__mocks__/styleMock.ts";

module.exports = {
  verbose: true,
  moduleNameMapper: mappedModuleAliases,
  coverageDirectory: "<rootDir>/client-coverage",
  // Instrument the WHOLE frontend tree, not just files a test happens to
  // import. Without collectCoverageFrom, Jest only counts files reached by an
  // import chain, so the reported number is a cherry-picked slice (~51% line)
  // rather than true whole-tree coverage. This makes the denominator honest.
  // Exclusions below are limited to non-executable / generated / test-support
  // code -- do NOT add real components here to inflate the number (#584).
  collectCoverageFrom: [
    "app/assets/src/**/*.{ts,tsx,js,jsx}",
    // Type-only declarations (no executable code).
    "!app/assets/src/**/*.d.ts",
    // Relay/GraphQL codegen artifacts -- never hand-written or tested.
    "!app/assets/src/**/__generated__/**",
    // Test files and Storybook stories are test-support, not app code.
    "!app/assets/src/**/*.test.{ts,tsx,js,jsx}",
    "!app/assets/src/**/*.stories.{ts,tsx,js,jsx}",
    // Test mocks/fixtures directories.
    "!app/assets/src/**/__mocks__/**",
    // Pure re-export barrels carry no logic worth covering.
    "!app/assets/src/**/index.{ts,js}",
    // Static image assets (non-TS, but guard anyway).
    "!app/assets/src/images/**",
  ],
  coveragePathIgnorePatterns: ["<rootDir>/node_modules/", "<rootDir>/build/"],
  coverageReporters: ["text-summary", "json", "html"],
  // RATCHET, not a target. These floors sit just below the true whole-tree
  // baseline measured with the honest collectCoverageFrom above. Re-measured
  // after coverage wave 1 landed (#244 utils/api, #245 common, #246 ui) on
  // Node 24.18.0, 2026-07-08: lines 11.31% / branches 9.01% / functions 9.64% /
  // stmts 11.35% (was 4.66 / 3.00 / 2.93 / 4.70 at the #240 baseline).
  // Flooring to the whole number below actual means CI fails only if coverage
  // REGRESSES -- coverage can only go up. Bump these floors upward as new specs
  // land (see COVERAGE-GAP-ANALYSIS-JEST-2026-07-07.md for the path to 90/90).
  // The old 55/35 thresholds "passed" against a biased slice and certified
  // nothing; these honest floors replace that fiction.
  coverageThreshold: {
    global: {
      branches: 9,
      functions: 9,
      lines: 11,
      statements: 11,
    },
  },
  globals: {},
  moduleDirectories: ["node_modules", "src"],
  moduleFileExtensions: ["ts", "tsx", "js", "jsx"],
  modulePaths: ["<rootDir>/"],
  rootDir: "./",
  testMatch: ["<rootDir>/**/**/*.test.{js,jsx,ts,tsx}"],
  testPathIgnorePatterns: ["<rootDir>/node_modules/", "<rootDir>/build/"],
};

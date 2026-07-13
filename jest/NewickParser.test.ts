// CZID-586 (#586) frontend coverage wave 1. NewickParser backs the phylo-tree /
// dendrogram visualizations (parses the Newick tree format the pipeline emits). It is
// self-contained pure logic (no React, no network) so it is cheap, deterministic
// branch coverage. These tests exercise every parse branch: nested clades, named /
// distanced leaves, the malformed-input error arms, and the token/id helpers.
import NewickParser from "../app/assets/src/components/utils/parsers/NewickParser";

describe("NewickParser.getUniqueId", () => {
  it("hands out strictly increasing ids", () => {
    const parser = new NewickParser("(A,B);");
    // The constructor already consumed id 0 for the root node.
    expect(parser.root.id).toBe(0);
    expect(parser.getUniqueId()).toBe(1);
    expect(parser.getUniqueId()).toBe(2);
  });
});

describe("NewickParser.createNode", () => {
  it("builds a node with defaults and a fresh id", () => {
    const parser = new NewickParser(";");
    const node = parser.createNode("leaf");
    expect(node).toMatchObject({ name: "leaf", distance: 0, children: [] });
    expect(typeof node.id).toBe("number");
  });

  it("respects an explicit distance", () => {
    const parser = new NewickParser(";");
    expect(parser.createNode("leaf", 1.5).distance).toBe(1.5);
  });
});

describe("NewickParser.getNextTokenAndSymbol", () => {
  it("reads the token up to the next structural symbol", () => {
    const parser = new NewickParser("Alpha,Beta);");
    const { token, symbol } = parser.getNextTokenAndSymbol(0);
    expect(token).toBe("Alpha");
    expect(symbol).toBe(",");
  });

  it("trims whitespace off the token", () => {
    const parser = new NewickParser("  Gamma ;");
    const { token } = parser.getNextTokenAndSymbol(0);
    expect(token).toBe("Gamma");
  });
});

describe("NewickParser.editNodeWithToken", () => {
  it("splits name and numeric distance", () => {
    const parser = new NewickParser(";");
    const node = parser.createNode();
    parser.editNodeWithToken(node, "leaf:2.5");
    expect(node.name).toBe("leaf");
    expect(node.distance).toBe(2.5);
  });

  it("throws when the token has too many colon-separated parts", () => {
    const parser = new NewickParser(";");
    const node = parser.createNode();
    expect(() => parser.editNodeWithToken(node, "a:1:extra")).toThrow(
      /Bad token/,
    );
  });
});

describe("NewickParser.parse", () => {
  it("parses a simple two-leaf tree into the root's children", () => {
    const parser = new NewickParser("(A,B);");
    const result = parser.parse();
    // parse() returns the parser instance on success.
    expect(result).toBe(parser);
    expect(parser.root.children).toHaveLength(2);
    expect(parser.root.children.map((c: { name: string }) => c.name)).toEqual([
      "A",
      "B",
    ]);
  });

  it("parses nested clades and leaf distances", () => {
    const parser = new NewickParser("((A:0.1,B:0.2):0.3,C:0.4);");
    parser.parse();
    expect(parser.root.children).toHaveLength(2);
    const [clade, leafC] = parser.root.children;
    expect(clade.children).toHaveLength(2);
    expect(clade.children[0].name).toBe("A");
    expect(clade.children[0].distance).toBeCloseTo(0.1);
    expect(leafC.name).toBe("C");
    expect(leafC.distance).toBeCloseTo(0.4);
  });

  it("returns null when a name precedes an open paren (bad format)", () => {
    // parse() begins at the first "(", so the offending name must sit inside the
    // tree: reading "A" and then hitting "(" trips the "Name should not preceed" guard.
    const parser = new NewickParser("(A(B,C));");
    // The error path is swallowed and parse() returns null.
    expect(parser.parse()).toBeNull();
  });

  it("returns null on an unrecognized structural symbol", () => {
    // getUnrootedTree relies on parse succeeding; feed an outright broken string.
    const parser = new NewickParser("(A,B]");
    expect(parser.parse()).toBeNull();
  });
});

describe("NewickParser.getOutput", () => {
  it("returns the (initially undefined) output field", () => {
    const parser = new NewickParser("(A,B);");
    expect(parser.getOutput()).toBeUndefined();
  });
});

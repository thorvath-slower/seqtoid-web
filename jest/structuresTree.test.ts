// CZID-462 (#586) coverage: app/assets/src/components/utils/structures/Tree.ts
import Tree from "../app/assets/src/components/utils/structures/Tree";

// Builds root -> a -> b (b is a leaf).
const buildLinearTree = () => {
  const b = { id: "b", name: "b", distance: 2, children: [] };
  const a = { id: "a", name: "a", distance: 1, children: [b] };
  const r = { id: "r", name: "r", distance: 0, children: [a] };
  return { r, a, b };
};

describe("structures/Tree.ts", () => {
  describe("fromNewickString", () => {
    it("returns null for an empty string", () => {
      expect(Tree.fromNewickString("")).toBeNull();
    });
    it("parses a newick string into a Tree with a root", () => {
      const tree = Tree.fromNewickString("(A:1,B:2);");
      expect(tree).not.toBeNull();
      expect(tree?.root).toBeDefined();
    });
  });

  describe("constructor with nodeData", () => {
    it("merges nodeData onto matching nodes by name", () => {
      const { r } = buildLinearTree();
      const tree = new Tree(r, { a: { highlighted: true } });
      const aNode = tree.bfs().find((n: any) => n.name === "a");
      expect(aNode.highlighted).toBe(true);
    });
  });

  describe("bfs", () => {
    it("returns nodes in breadth-first order", () => {
      const { r } = buildLinearTree();
      const tree = new Tree(r, null);
      expect(tree.bfs().map((n: any) => n.id)).toEqual(["r", "a", "b"]);
    });
  });

  describe("ancestors", () => {
    it("returns the path from the target node up to the root", () => {
      const { r } = buildLinearTree();
      const tree = new Tree(r, null);
      expect(tree.ancestors(r, "b").map((n: any) => n.id)).toEqual([
        "b",
        "a",
        "r",
      ]);
    });
    it("returns null when the node id is not present", () => {
      const { r } = buildLinearTree();
      const tree = new Tree(r, null);
      expect(tree.ancestors(r, "missing")).toBeNull();
    });
  });

  describe("rerootTree", () => {
    it("makes the requested node the new root", () => {
      const { r } = buildLinearTree();
      const tree = new Tree(r, null);
      tree.rerootTree("b");
      expect(tree.root.id).toBe("b");
      // The old root should now be a descendant.
      expect(
        tree
          .bfs()
          .map((n: any) => n.id)
          .sort(),
      ).toEqual(["a", "b", "r"]);
    });
  });
});

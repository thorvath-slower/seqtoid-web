// #586 (epic #462) coverage: utils/memo wraps React.memo but proxies displayName
// through to the inner component (custom get/set descriptor). Verifies the wrapper
// memoizes and that displayName round-trips to the wrapped component.
import React from "react";
import { memo } from "../app/assets/src/components/utils/memo";

describe("memo", () => {
  it("returns a React.memo-wrapped component ($$typeof memo symbol)", () => {
    const Inner = () => <div />;
    const Wrapped = memo(Inner);
    expect((Wrapped as any).$$typeof).toBe(Symbol.for("react.memo"));
  });

  it("proxies displayName assignment onto the wrapped component", () => {
    const Inner: React.FC = () => <div />;
    const Wrapped = memo(Inner);
    (Wrapped as any).displayName = "MyComponent";
    expect(Inner.displayName).toBe("MyComponent");
    expect((Wrapped as any).displayName).toBe("MyComponent");
  });
});

#!/bin/bash
# CZID-420: surface TS errors HIDDEN behind the CZID-8698 strictNullCheck `@ts-expect-error`
# suppressions. We neutralize those directives (strip the `@ts-expect-error` token, keeping the line
# and the CZID-8698 marker intact) and run tsc WITHOUT strictNullChecks: the null-check errors the
# directives were suppressing disappear, so anything tsc still reports is a genuinely hidden,
# non-null error worth fixing.
#
# This replaces the old scripts/uncomment-check.ts, which generated per-line `sed` deletes from a
# fragile colon-split parse. It crashed on inline / JSX directive forms (`? // @ts-expect-error`,
# `{/* @ts-expect-error */}`), leaving some directives in place and failing the check with spurious
# "unused '@ts-expect-error'" (TS2578) errors on files processed after the crash.
if [[ `git status --porcelain` ]]; then
  echo "Commit your changes and then try rerunning this script. ❌"
  exit 1
fi

# `sed -i` takes a mandatory backup-suffix arg on BSD/macOS but not on GNU/Linux (CI).
if [[ "$OSTYPE" == "darwin"* ]]; then
  sedi=(sed -i '')
else
  sedi=(sed -i)
fi

echo "Temporarily neutralizing // @ts-expect-error CZID-8698 directives..."
grep -rl "@ts-expect-error CZID-8698" app/assets/src | while read -r file; do
  "${sedi[@]}" 's/@ts-expect-error CZID-8698/CZID-8698/g' "$file"
done

echo "Checking for TSC errors hidden by the CZID-8698 @ts-expect-error comments..."
npx tsc -p ./app/assets/tsconfig.json --strictNullChecks false --noemit
status=$?

echo "Restoring // @ts-expect-error comments..."
git restore .
git clean -f

if [ "$status" -eq 0 ]; then
  echo "Congrats! No errors found. ✅"
  exit 0
else
  echo "TSC errors found 👀. Please fix them before committing. ❌"
  exit 1
fi

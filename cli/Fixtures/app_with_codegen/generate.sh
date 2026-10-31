#!/bin/sh
# Runs all three generators the way Tuist would.
#
# This doubles as the executable specification of the environment contract: if a
# value below had to be hand-computed in a way Tuist could not, the contract would be
# wrong. Note what Tuist supplies and the generators therefore never recompute: resolved
# absolute input paths with globs already expanded, and the output directory itself, created
# before the generator is invoked.
#
# What it deliberately does NOT reproduce is Tuist's staging and swap: each output directory
# is written fresh, moved into place after a zero exit, and recorded by an action hash under
# Derived/CodeGen/State/. That lifecycle is invisible to a generator, so simulating it here
# would obscure the contract rather than document it. The one visible consequence is noted
# in each script's header: the directory handed over is not its final location.
#
# It also exists out of necessity. Generated output cannot be committed, since `**/Derived/`
# is gitignored and generated output lives under `Derived/CodeGen/`. A fresh clone therefore
# has no generated files, which is the state the design has to work from and the reason the
# action hash comes from the declaration rather than from output bytes.
set -e

ROOT=$(cd "$(dirname "$0")" && pwd)
rm -rf "$ROOT"/Projects/*/Derived
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

json_inputs() {
    # $@ = type:path pairs, in declaration order. `.script` inputs are absent: they
    # contribute stdout to the hash and are not paths.
    printf '%s\n' "$@" | /usr/bin/python3 -c 'import json,sys
print(json.dumps([{"type": t, "path": p} for t, p in
                  (l.rstrip("\n").split(":", 1) for l in sys.stdin)], indent=2))'
}

# ── Per-target: AccountUI's own catalogs → accessors ─────────────────────────────────────
ASSETS_OUT="$ROOT/Projects/DesignSystem/Derived/CodeGen/Targets/AccountUI/assets"
mkdir -p "$ASSETS_OUT/Sources"
json_inputs \
    "folder:$ROOT/Projects/DesignSystem/Sources/AccountUI/Resources" \
    "file:$ROOT/templates/Assets.stencil" > "$WORK/assets-inputs.json"

env \
    TUIST_ROOT_DIR="$ROOT" \
    TUIST_PROJECT_DIR="$ROOT/Projects/DesignSystem" \
    TUIST_TARGET_NAME="AccountUI" \
    TUIST_INPUTS_FILE="$WORK/assets-inputs.json" \
    TUIST_OUTPUT_SOURCES_DIR="$ASSETS_OUT/Sources" \
    "$ROOT/Codegen/swiftgen-assets.sh"

# ── Per-target, second generator on the same target: one catalog → typed accessors ───────
STRINGS_OUT="$ROOT/Projects/DesignSystem/Derived/CodeGen/Targets/AccountUI/strings"
mkdir -p "$STRINGS_OUT/Sources"
json_inputs "file:$ROOT/Projects/DesignSystem/Strings/en.json" > "$WORK/strings-inputs.json"

env \
    TUIST_ROOT_DIR="$ROOT" \
    TUIST_PROJECT_DIR="$ROOT/Projects/DesignSystem" \
    TUIST_TARGET_NAME="AccountUI" \
    TUIST_INPUTS_FILE="$WORK/strings-inputs.json" \
    TUIST_OUTPUT_SOURCES_DIR="$STRINGS_OUT/Sources" \
    STRINGS_ACCESS_LEVEL="public" \
    "$ROOT/Codegen/strings.sh"

# ── Code generation target: one Apollo run feeding GQLSchema and GQLTypes ──────────────────────────
GQL_OUT="$ROOT/Projects/Core/Derived/CodeGen/Producers/GQLCodegen"
mkdir -p "$GQL_OUT/GQLSchema/Sources" "$GQL_OUT/GQLTypes/Sources"

# `.glob("//Projects/**/*.graphql")` arrives expanded to one `file` entry per match.
# `-not -path '*/Derived/*'` because Tuist never expands a glob into `Derived`, so a
# generator emitting a `.graphql` can't feed its own output back into its hash.
set -- "file:$ROOT/Codegen/schema.graphqls"
for OP in $(find "$ROOT/Projects" -name '*.graphql' -not -path '*/Derived/*' | sort); do
    set -- "$@" "file:$OP"
done
json_inputs "$@" > "$WORK/gql-inputs.json"

# An array rather than an object keyed by target, because target names are not unique across
# projects: a producer can legitimately feed a `Models` target in two of them.
cat > "$WORK/gql-outputs.json" <<EOF
[
  { "project": "//Projects/Core", "target": "GQLSchema", "path": "$GQL_OUT/GQLSchema/Sources" },
  { "project": "//Projects/Core", "target": "GQLTypes",  "path": "$GQL_OUT/GQLTypes/Sources" }
]
EOF

env \
    TUIST_ROOT_DIR="$ROOT" \
    TUIST_PROJECT_DIR="$ROOT/Projects/Core" \
    TUIST_TARGET_NAME="GQLCodegen" \
    TUIST_INPUTS_FILE="$WORK/gql-inputs.json" \
    TUIST_OUTPUTS_FILE="$WORK/gql-outputs.json" \
    "$ROOT/Codegen/apollo.sh"

echo "Generated:"
find "$ROOT/Projects" -path '*Derived*' -type f | sed "s|$ROOT/||" | sort

cd zml
echo "Starting Bazel build..."
bazel build //zml:docs
cd ..
# we reference these outputs in build.zig
# - ./zml/bazel-bin/zml/docs.docs/sources.tar
# - ./zml/bazel-bin/zml/docs.docs/main.wasm
cd WORKSPACE
echo "Starting Zine build..."
zig build $@

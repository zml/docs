cd zml
echo "Starting Bazel build..."
bazel build //zml:sources
cd ..
cp ./zml/bazel-bin/zml/sources.tar WORKSPACE/

cd WORKSPACE
echo "Starting Zine build..."
zig build $@

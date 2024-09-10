cd zml
bazel build //zml:docs
cd ..
# we reference these outputs in build.zig
# cp ./zml/bazel-bin/zml/docs.docs/sources.tar .
# cp ./zml/bazel-bin/zml/docs.docs/sources.tar .
cd WORKSPACE
zig build $@

cd zml
# We don't use bazel build //zml:sources
# because it pulls too many files.
# Some could be useful like sentencepiece.pb.zig,
# but they aren't properly put in places where the wasm code expects them,
# resulting in broken links + polluting the search bar.
tar -cf sources.tar zml/*.zig zml/**/*.zig
cd ..

cp -f ./zml/sources.tar WORKSPACE/
cp -v ./build.zig* WORKSPACE/

cd WORKSPACE
echo "Starting Zine build..."
zig build $@

cd zml
# We don't use bazel build //zml:sources
# because it pulls too many files.
# Some could be useful like sentencepiece.pb.zig,
# but they aren't properly put in places where the wasm code expects them,
# resulting in broken links + polluting the search bar.
if tar --version | grep bsdtar ; then
    echo BSD TAR
    MAC_TAR_DISABLE_STUFF_FLAG=--no-mac-metadata
fi

tar $MAC_TAR_DISABLE_STUFF_FLAG -cf sources.tar zml/*.zig zml/**/*.zig
cd ..

cp -f ./zml/sources.tar WORKSPACE/
cp -v ./build.zig* WORKSPACE/


cd WORKSPACE


echo "Starting Zine build..."
zig build $@

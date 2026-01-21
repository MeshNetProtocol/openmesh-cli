make -C go-cli-lib apple

rm -rf openmesh-apple/lib/OpenMeshGo.xcframework
cp -R go-cli-lib/lib/OpenMeshGo.xcframework openmesh-apple/lib/OpenMeshGo.xcframework

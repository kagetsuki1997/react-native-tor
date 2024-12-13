# Prepare
- Andriod
    - Simulator: https://dev.to/mochafreddo/setting-up-and-managing-android-emulators-on-macos-with-homebrew-3fg0
    - `node patches/patch-sifir_android.mjs`
    - remove `package` from `node_modules/react-native-tor/android/src/main/AndroidManifest.xml`
    - add `namespace "com.reactnativetor"` to `node_modules/react-native-tor/android/build.gradle`

# Possible Issue
- https://stackoverflow.com/questions/63607158/xcode-building-for-ios-simulator-but-linking-in-an-object-file-built-for-ios-f
- https://stackoverflow.com/questions/79204968/react-native-0-73-9-build-fails-with-unresolved-reference-serviceof-in-react

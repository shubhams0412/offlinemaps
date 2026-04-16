# Valhalla (iOS)

This app can use **real Valhalla routing on iOS** by linking a vendored
`Valhalla.xcframework`.

Until the framework is built, the project compiles against **stub headers**
in `native_include/valhalla`, which produces **straight-line routes** (2 points).

## Build the framework

Run:

```sh
./scripts/build_valhalla_ios.sh
```

Expected output:

- `ios/valhalla/Valhalla.xcframework`

Then rebuild iOS (Flutter will run `pod install` and pick up the local pod):

```sh
flutter clean
flutter run -d "<your device>"
```

## Notes

- Building Valhalla for iOS is CPU/RAM heavy and can take a while.
- You need Valhalla dependencies for iOS (Boost, protobuf, sqlite, etc.). The
  build script prints the exact prerequisites and steps.


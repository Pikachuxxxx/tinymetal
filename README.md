# TinyMetal

Minimal native Metal boilerplate for Apple platforms with:

- Objective-C app code
- Separate `.metal` shaders
- CMake-only project generation
- Native Cocoa on macOS
- Native UIKit on iOS

## Do we have C bindings?

No official pure C bindings exist for Cocoa, UIKit, or Metal.

- `Cocoa` and `UIKit` are Objective-C APIs.
- `Metal` is also an Objective-C API.
- `Objective-C++` is not required here.
- You only need `Objective-C++` if you want to mix C++ with Apple's Objective-C frameworks.

So the smallest native setup is:

- C for plain shared logic if you want it
- Objective-C for app/window/view integration and Metal calls

## Configure

This project is designed for the Xcode CMake generator.

### macOS

```bash
cmake -S . -B build/macos -G Xcode -DTINYMETAL_PLATFORM=macOS
cmake --build build/macos --config Debug
open build/macos/Debug/TinyMetal.app
```

### iOS

```bash
cmake -S . -B build/ios -G Xcode -DTINYMETAL_PLATFORM=iOS
cmake --build build/ios --config Debug
```

Open the generated Xcode project if you want to run the iOS app in Simulator or on a device.

## Layout

- `src/shared`: shared renderer and shaders
- `src/macos`: Cocoa entrypoint and native macOS view
- `src/ios`: UIKit entrypoint and native iOS view
- `cmake`: bundle metadata templates

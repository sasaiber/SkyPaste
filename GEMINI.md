# SkyPaste Project Instructions

## Build Workflow
- Always use `bash build.sh` to build the application. This script compiles the app and outputs it to the `build/SkyPaste.app` directory. Do not use standard `swift build` for the final app packaging unless specifically requested, as `build.sh` handles the proper app bundle generation.
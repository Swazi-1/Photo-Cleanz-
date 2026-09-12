# Photo-Cleanz

This repository includes a GitHub Actions builder for an unsigned iOS IPA.

## Use the builder

1. Add the iOS app source, including one `.xcodeproj` or `.xcworkspace`, to the repository.
2. Make sure the app scheme is shared (`Manage Schemes…` in Xcode).
3. Push the app source to `main` for an automatic build, or open **Actions → Build unsigned IPA → Run workflow** for a manual build.
4. Leave the path and scheme fields blank for automatic discovery, or provide them when the repository contains more than one project/workspace.
5. Download the `Photo-Cleanz-IPA-*` artifact from the completed run.

The workflow archives for a generic iOS device and packages the app as `Payload/<App>.app` inside the IPA. It deliberately disables Apple code signing, so the artifact must be re-signed by AltStore/SideStore or another provisioning workflow before installing on a device. It is not an App Store distribution build.

The repository is currently empty of app source, so the workflow will stop with a clear error until an Xcode project or workspace is added.

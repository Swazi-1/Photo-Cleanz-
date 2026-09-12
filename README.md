# Photo-Cleanz

This repository contains a SwiftUI photo-review app and a GitHub Actions builder for an unsigned iOS IPA.

## Use the builder

1. The app source is under `Sources/`, and `project.yml` generates `PhotoCleanz.xcodeproj` with XcodeGen; a hand-authored `.xcodeproj` or `.xcworkspace` also works.
2. If you use a hand-authored project, make sure the app scheme is shared (`Manage Schemes…` in Xcode).
3. Push the app source to `main` for an automatic build, or open **Actions → Build unsigned IPA → Run workflow** for a manual build.
4. Leave the path and scheme fields blank for automatic discovery, or provide them when the repository contains more than one project/workspace.
5. Download the `Photo-Cleanz-IPA-*` artifact from the completed run.

The workflow archives for a generic iOS device and packages the app as `Payload/<App>.app` inside the IPA. It deliberately disables Apple code signing, so the artifact must be re-signed by AltStore/SideStore or another provisioning workflow before installing on a device. It is not an App Store distribution build.

The included app uses Apple PhotoKit authorization, asset fetching, image requests, and change requests. Photos stay untouched while you review; only the items you mark and confirm are sent to Photos for deletion.

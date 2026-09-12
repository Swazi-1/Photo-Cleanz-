#!/usr/bin/env bash

set -Eeuo pipefail

fail() {
  echo "::error::$*" >&2
  exit 1
}

repo_root="${GITHUB_WORKSPACE:-$(pwd)}"
cd "$repo_root"

configuration="${CONFIGURATION:-Release}"
requested_workspace="${WORKSPACE_PATH:-}"
requested_project="${PROJECT_PATH:-}"
requested_scheme="${SCHEME:-}"

if [[ -n "$requested_workspace" && -n "$requested_project" ]]; then
  fail "Set only one of WORKSPACE_PATH or PROJECT_PATH."
fi

build_target=()
container_path=""

if [[ -n "$requested_workspace" ]]; then
  [[ -d "$requested_workspace" ]] || fail "Workspace not found: $requested_workspace"
  [[ "$requested_workspace" == *.xcworkspace ]] || fail "WORKSPACE_PATH must point to a .xcworkspace"
  build_target=(-workspace "$requested_workspace")
  container_path="$requested_workspace"
elif [[ -n "$requested_project" ]]; then
  [[ -d "$requested_project" ]] || fail "Project not found: $requested_project"
  [[ "$requested_project" == *.xcodeproj ]] || fail "PROJECT_PATH must point to a .xcodeproj"
  build_target=(-project "$requested_project")
  container_path="$requested_project"
else
  # Every .xcodeproj contains an internal project.xcworkspace. It is not an
  # app workspace and must not win automatic discovery.
  workspaces=()
  while IFS= read -r workspace; do
    workspaces+=("$workspace")
  done < <(find . -maxdepth 5 -type d -name '*.xcworkspace' -not -path '*/*.xcodeproj/project.xcworkspace' -not -path '*/Pods/*' -print | sort)

  projects=()
  while IFS= read -r project; do
    projects+=("$project")
  done < <(find . -maxdepth 5 -type d -name '*.xcodeproj' -not -path '*/Pods/*' -print | sort)

  if (( ${#workspaces[@]} == 1 )); then
    container_path="${workspaces[0]}"
    build_target=(-workspace "$container_path")
  elif (( ${#workspaces[@]} > 1 )); then
    printf '%s\n' "${workspaces[@]}"
    fail "Multiple workspaces found; set WORKSPACE_PATH to the app workspace."
  elif (( ${#projects[@]} == 1 )); then
    container_path="${projects[0]}"
    build_target=(-project "$container_path")
  elif (( ${#projects[@]} > 1 )); then
    printf '%s\n' "${projects[@]}"
    fail "Multiple projects found; set PROJECT_PATH to the app project."
  else
    fail "No .xcodeproj or .xcworkspace found. Add the iOS app source, then run this workflow again."
  fi
fi

echo "Using Xcode container: $container_path"

if [[ -n "$requested_scheme" ]]; then
  scheme="$requested_scheme"
else
  command -v jq >/dev/null 2>&1 || fail "jq is required to discover a shared Xcode scheme; set SCHEME explicitly."
  list_json="$(xcodebuild "${build_target[@]}" -list -json)" || fail "Unable to list schemes from $container_path"
  if [[ "$container_path" == *.xcworkspace ]]; then
    scheme="$(jq -r '.workspace.schemes[0] // empty' <<<"$list_json")"
  else
    scheme="$(jq -r '.project.schemes[0] // empty' <<<"$list_json")"
  fi
  [[ -n "$scheme" ]] || fail "No shared scheme found. Share an app scheme in Xcode or set SCHEME explicitly."
fi

echo "Using scheme: $scheme"
echo "Using configuration: $configuration"

build_root="${RUNNER_TEMP:-${repo_root}/.build}/photo-cleanz"
archive_path="$build_root/${scheme}.xcarchive"
derived_data_path="$build_root/DerivedData"
output_dir="$repo_root/dist"

rm -rf "$build_root"
mkdir -p "$build_root" "$output_dir"
rm -rf "$output_dir/Payload"
for old_ipa in "$output_dir"/Photo-Cleanz-*.ipa; do
  [[ -e "$old_ipa" ]] && rm -f "$old_ipa"
done

xcodebuild \
  "${build_target[@]}" \
  -scheme "$scheme" \
  -configuration "$configuration" \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive_path" \
  -derivedDataPath "$derived_data_path" \
  -sdk iphoneos \
  clean archive \
  SKIP_INSTALL=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=''

app_bundles=()
while IFS= read -r app_bundle; do
  app_bundles+=("$app_bundle")
done < <(find "$archive_path/Products/Applications" -maxdepth 1 -type d -name '*.app' -print | sort)
(( ${#app_bundles[@]} == 1 )) || fail "Expected one application bundle in the archive; found ${#app_bundles[@]}."
app_path="${app_bundles[0]}"

info_plist="$app_path/Info.plist"
[[ -f "$info_plist" ]] || fail "Missing Info.plist in $app_path"
bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")" || fail "Could not read CFBundleIdentifier"
executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist")" || fail "Could not read CFBundleExecutable"
[[ -f "$app_path/$executable_name" ]] || fail "Missing app executable: $executable_name"

ipa_name="Photo-Cleanz-${GITHUB_RUN_NUMBER:-local}.ipa"
mkdir -p "$output_dir/Payload"
ditto "$app_path" "$output_dir/Payload/$(basename "$app_path")"
(cd "$output_dir" && /usr/bin/zip -qry "$ipa_name" Payload)
rm -rf "$output_dir/Payload"

echo "Created $output_dir/$ipa_name"
echo "Bundle identifier: $bundle_identifier"
echo "App bundle: $(basename "$app_path")"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## IPA build complete"
    echo
    echo "- Scheme: `$scheme`"
    echo "- Configuration: `$configuration`"
    echo "- Bundle identifier: `$bundle_identifier`"
    echo "- Artifact: `$ipa_name`"
    echo "- Signing: unsigned (for sideloading/re-signing)"
  } >> "$GITHUB_STEP_SUMMARY"
fi

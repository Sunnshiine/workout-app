#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_path="$root_dir/WorkoutTracker.xcodeproj"
scheme="${SCHEME:-WorkoutTracker}"
configuration="${CONFIGURATION:-Release}"
marketing_version="${MARKETING_VERSION:-1.0}"
build_number="${CURRENT_PROJECT_VERSION:-${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}}"
archive_root="${ARCHIVE_ROOT:-$root_dir/build/TestFlight}"
archive_path="${ARCHIVE_PATH:-$archive_root/WorkoutTracker-$marketing_version-$build_number.xcarchive}"
derived_data_path="${DERIVED_DATA_PATH:-$archive_root/DerivedData}"
export_path="${EXPORT_PATH:-$archive_root/Upload}"
export_options="${EXPORT_OPTIONS_PLIST:-$root_dir/Config/TestFlightExportOptions.plist}"

if [[ ! -f "$root_dir/Secrets.xcconfig" ]]; then
  echo "Missing Secrets.xcconfig. Copy Secrets.xcconfig.template and fill in the Google OAuth values for the release bundle ID." >&2
  exit 1
fi

if [[ ! -f "$export_options" ]]; then
  echo "Missing export options plist: $export_options" >&2
  exit 1
fi

provisioning_args=()
if [[ "${ALLOW_PROVISIONING_UPDATES:-1}" == "1" ]]; then
  provisioning_args+=("-allowProvisioningUpdates")
fi

if [[ -n "${APP_STORE_CONNECT_API_KEY_PATH:-}" || -n "${APP_STORE_CONNECT_KEY_ID:-}" || -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  if [[ -z "${APP_STORE_CONNECT_API_KEY_PATH:-}" || -z "${APP_STORE_CONNECT_KEY_ID:-}" || -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
    echo "Set APP_STORE_CONNECT_API_KEY_PATH, APP_STORE_CONNECT_KEY_ID, and APP_STORE_CONNECT_ISSUER_ID together." >&2
    exit 1
  fi
  provisioning_args+=(
    "-authenticationKeyPath" "$APP_STORE_CONNECT_API_KEY_PATH"
    "-authenticationKeyID" "$APP_STORE_CONNECT_KEY_ID"
    "-authenticationKeyIssuerID" "$APP_STORE_CONNECT_ISSUER_ID"
  )
fi

mkdir -p "$archive_root" "$export_path"

echo "Archiving $scheme $marketing_version ($build_number)..."
xcodebuild archive \
  -project "$project_path" \
  -scheme "$scheme" \
  -configuration "$configuration" \
  -destination "generic/platform=iOS" \
  -archivePath "$archive_path" \
  -derivedDataPath "$derived_data_path" \
  -skipPackagePluginValidation \
  "${provisioning_args[@]}" \
  MARKETING_VERSION="$marketing_version" \
  CURRENT_PROJECT_VERSION="$build_number"

echo "Uploading archive to App Store Connect..."
xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$export_options" \
  "${provisioning_args[@]}"

echo "Uploaded $scheme $marketing_version ($build_number) to App Store Connect for TestFlight processing."

#!/usr/bin/env bash
set -euo pipefail

# Boots the ADR-0007 pinned device (iPhone 17 Pro, iOS 27.0) for the Visual Regression gate.
# A freshly booted device launches dozens of system daemons (wallpaper posters, widget
# extensions, Health, Siri, Apple Intelligence) that saturate a 3 vCPU runner for minutes
# while xcodebuild waits. None of them take part in rendering the app, so they stay off.

RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-27-0"
DEVICE="iPhone 17 Pro"

DISABLED_JOBS=(
    com.apple.PosterBoard
    com.apple.chronod
    com.apple.contacts.postersyncd
    com.apple.healthd
    com.apple.healthappd
    com.apple.healthcontentd
    com.apple.healtheventsd
    com.apple.healthrecordsd
    com.apple.finhealthd
    com.apple.fitnesscoachingd
    com.apple.fitnessintelligenced
    com.apple.activitysharingd
    com.apple.siriactionsd
    com.apple.siriinferenced
    com.apple.siriknowledged
    com.apple.sirittsd
    com.apple.siri.acousticsignature
    com.apple.siri.context.service
    com.apple.assistantd
    com.apple.assistant_service
    com.apple.assistant_cdmd
    com.apple.routined
    com.apple.CoreRoutine.helperservice
    com.apple.itunesstored
    com.apple.itunescloudd
    com.apple.email.maild
    com.apple.mobileassetd
    com.apple.MobileAsset.ManifestStorageService
    com.apple.ScreenTimeAgent
    com.apple.ScreenTimeSettingsAgent
    com.apple.Maps.mapssyncd
    com.apple.apsd
    com.apple.identityservicesd
    com.apple.sharingd
    com.apple.devicesharingd
    com.apple.newsd
    com.apple.nanonewscd
    com.apple.nanotimekitcompaniond
    com.apple.linkd
    com.apple.tzlinkd
    com.apple.remoteappintentsd
    com.apple.mediaanalysisd
    com.apple.photoanalysisd
    com.apple.corespotlightservice
    com.apple.spotlightknowledged
    com.apple.spotlightknowledged.updater
    com.apple.suggestd
    com.apple.knowledgeconstructiond
    com.apple.biomed
    com.apple.biomesyncd
    com.apple.intelligencecontextd
    com.apple.intelligenceflowd
    com.apple.intelligenceplatformd
    com.apple.intelligencetasksd
    com.apple.callintelligenced
    com.apple.triald
    com.apple.cloudd
    com.apple.bird
    com.apple.gamed
    com.apple.homed
    com.apple.passd
    com.apple.weatherd
    com.apple.dasd
)

udid=$(xcrun simctl list devices available -j |
    jq -r --arg runtime "$RUNTIME" --arg name "$DEVICE" '.devices[$runtime][]? | select(.name == $name) | .udid' |
    head -1)
if [[ -z $udid ]]; then
    echo "::error::No available $DEVICE on $RUNTIME; move the ADR-0007 pin with the runner image."
    exit 70
fi

args=()
for job in "${DISABLED_JOBS[@]}"; do
    args+=("--disabledJob=$job")
done

start=$(date +%s)
xcrun simctl boot "$udid" "${args[@]}"
xcrun simctl bootstatus "$udid"
echo "booted $DEVICE ($udid) in $(($(date +%s) - start))s with ${#DISABLED_JOBS[@]} jobs disabled"

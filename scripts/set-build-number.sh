#!/bin/sh
# Release builds only: stamp the built Info.plist with the git commit count as
# CFBundleVersion, so every archive gets a new, increasing build number without
# editing the project. The app and its widget run this same script, so their
# numbers always match (App Store Connect rejects a mismatch).
set -eu

[ "${CONFIGURATION}" = "Release" ] || exit 0

build=$(git -C "${SRCROOT}" rev-list --count HEAD)
if [ -n "$(git -C "${SRCROOT}" status --porcelain)" ]; then
    echo "warning: uncommitted changes; build ${build} may repeat the number of the next archive"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${build}" "${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
echo "CFBundleVersion = ${build}"

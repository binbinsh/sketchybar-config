#!/bin/bash

source .env

codesign --sign "${APPLE_DEVELOPER_ID}" \
  --force --options runtime --timestamp \
  helpers/event_providers/location/bin/SketchyBarLocationHelper.app/Contents/MacOS/SketchyBarLocationHelper

codesign --sign "${APPLE_DEVELOPER_ID}" \
  --force --options runtime --timestamp \
  helpers/event_providers/location/bin/SketchyBarLocationHelper.app

/usr/bin/codesign --verify --deep --strict --verbose=2 \
  helpers/event_providers/location/bin/SketchyBarLocationHelper.app

/usr/bin/ditto -c -k --keepParent helpers/event_providers/location/bin/SketchyBarLocationHelper.app SketchyBarLocationHelper.zip

xcrun notarytool submit SketchyBarLocationHelper.zip --keychain-profile "${APPLE_NOTARIZE_PROFILE}" --wait

xcrun stapler staple helpers/event_providers/location/bin/SketchyBarLocationHelper.app

spctl --assess --type execute -vv helpers/event_providers/location/bin/SketchyBarLocationHelper.app

rm SketchyBarLocationHelper.zip

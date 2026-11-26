#!/bin/zsh
# Compiles the pure logic with its checks and runs them.
set -e
cd "${0:A:h}/.."
out="$(mktemp -d)/logic-tests"
xcrun swiftc -swift-version 6 -D DEBUG -o "$out" \
  Expo/Domain/*.swift \
  Expo/Services/System/AppConfig.swift \
  Expo/Services/Backend/BackendClient.swift \
  Expo/Services/Audio/PCMFrameMixer.swift \
  Tests/LogicTests.swift
"$out"

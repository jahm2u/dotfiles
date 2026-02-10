#!/usr/bin/env swift
// Creates a Multi-Output Device from all connected LG UltraFine displays
// Usage: swift create-multi-output.swift

import CoreAudio
import Foundation

func getDeviceUID(_ deviceID: AudioDeviceID) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var uid: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
    return status == noErr ? uid as String : nil
}

func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceNameCFString,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var name: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
    return status == noErr ? name as String : nil
}

func hasOutputStreams(_ deviceID: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
    return status == noErr && size > 0
}

func getAllDeviceIDs() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: count)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices)
    return devices
}

// Check if a Multi-Output device already exists with LG sub-devices
let allDevices = getAllDeviceIDs()
for deviceID in allDevices {
    if let name = getDeviceName(deviceID),
       (name.contains("Multi-Output") || name.contains("LG Dual")) {
        print("Multi-Output device already exists: \(name)")
        exit(0)
    }
}

// Find LG UltraFine output devices
var lgUIDs: [String] = []
for deviceID in allDevices {
    if let name = getDeviceName(deviceID),
       let uid = getDeviceUID(deviceID),
       name.contains("LG UltraFine"),
       hasOutputStreams(deviceID) {
        lgUIDs.append(uid)
        print("Found LG output: \(uid)")
    }
}

guard lgUIDs.count >= 2 else {
    print("Error: Need at least 2 LG UltraFine output devices, found \(lgUIDs.count)")
    exit(1)
}

// Build the aggregate device description
let subDevices: [[String: Any]] = lgUIDs.map { uid in
    [kAudioSubDeviceUIDKey as String: uid]
}

let description: [String: Any] = [
    kAudioAggregateDeviceUIDKey as String: "com.user.lg-dual-output",
    kAudioAggregateDeviceNameKey as String: "LG Dual",
    kAudioAggregateDeviceSubDeviceListKey as String: subDevices,
    kAudioAggregateDeviceIsStackedKey as String: 0  // 0 = Multi-Output (not aggregate)
]

var aggregateDeviceID: AudioDeviceID = 0
let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateDeviceID)

if status == noErr {
    print("Created Multi-Output device 'LG Dual' (ID: \(aggregateDeviceID))")
} else {
    print("Error creating device: \(status)")
    exit(1)
}

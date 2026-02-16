#!/usr/bin/env swift
// Creates a Multi-Output Device from all connected LG UltraFine displays
// Destroys any existing programmatic device first to ensure correct config
// Enables drift correction on slave sub-device for reliable dual playback
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

// Phase 1: Destroy any existing aggregate devices we own or that conflict
let allDevices = getAllDeviceIDs()
for deviceID in allDevices {
    guard let uid = getDeviceUID(deviceID),
          let name = getDeviceName(deviceID) else { continue }

    // Destroy our own programmatic device if it exists
    if uid == "com.user.lg-dual-output" {
        let status = AudioHardwareDestroyAggregateDevice(deviceID)
        if status == noErr {
            print("Destroyed existing LG Dual device")
        } else {
            print("Warning: Could not destroy existing LG Dual (status: \(status))")
        }
        continue
    }

    // Try to destroy system-created multi-output devices (Audio MIDI Setup ones)
    if name.contains("Multi-Output") || name.contains("Aggregate") ||
       (name.contains("LG") && name.contains("Dual")) ||
       (name.contains("LG") && name.contains("Output") && uid.contains("AMS")) {
        let status = AudioHardwareDestroyAggregateDevice(deviceID)
        if status == noErr {
            print("Destroyed system multi-output device: \(name)")
        } else {
            print("Warning: Could not destroy '\(name)' (status: \(status)) — delete it manually in Audio MIDI Setup")
        }
    }
}

// Brief pause for CoreAudio to process destructions
usleep(200_000)

// Phase 2: Find LG UltraFine output devices
var lgUIDs: [String] = []
let refreshedDevices = getAllDeviceIDs()
for deviceID in refreshedDevices {
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

// Phase 3: Build the multi-output device with drift correction
// First device = clock master, second device = slave with drift correction
let subDevices: [[String: Any]] = lgUIDs.enumerated().map { (index, uid) in
    var dict: [String: Any] = [kAudioSubDeviceUIDKey as String: uid]
    if index > 0 {
        // Enable drift correction on slave devices to keep them in sync
        dict[kAudioSubDeviceDriftCompensationKey as String] = 1 as UInt32
    }
    return dict
}

let description: [String: Any] = [
    kAudioAggregateDeviceUIDKey as String: "com.user.lg-dual-output",
    kAudioAggregateDeviceNameKey as String: "LG Dual",
    kAudioAggregateDeviceSubDeviceListKey as String: subDevices,
    kAudioAggregateDeviceIsStackedKey as String: 1 as UInt32,  // 1 = Stacked (Multi-Output: same audio to all sub-devices)
    kAudioAggregateDeviceMasterSubDeviceKey as String: lgUIDs[0]
]

var aggregateDeviceID: AudioDeviceID = 0
let createStatus = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateDeviceID)

if createStatus != noErr {
    print("Error creating device: \(createStatus)")
    exit(1)
}

// Verify sub-device count
func getAggregateSubDevices(_ aggID: AudioDeviceID) -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioAggregateDevicePropertyActiveSubDeviceList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(aggID, &address, 0, nil, &size) == noErr else { return [] }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var subIDs = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(aggID, &address, 0, nil, &size, &subIDs) == noErr else { return [] }
    return subIDs
}

let subDeviceIDs = getAggregateSubDevices(aggregateDeviceID)
for (index, subID) in subDeviceIDs.enumerated() {
    let subName = getDeviceName(subID) ?? "unknown"
    print("  [\(index)] \(subName) — \(index == 0 ? "clock master" : "slave (drift correction via creation dict)")")
}

print("Created Multi-Output device 'LG Dual' (ID: \(aggregateDeviceID), \(subDeviceIDs.count) sub-devices)")

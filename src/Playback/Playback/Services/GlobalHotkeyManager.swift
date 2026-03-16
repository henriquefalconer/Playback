// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import Carbon
import os

enum HotkeyError: Error {
    case registrationFailed
    case alreadyRegistered
    case accessibilityPermissionDenied
}

@MainActor
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    private var hotkey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var callback: (() -> Void)?

    private init() {}

    func register(keyCode: UInt32, modifiers: UInt32, callback: @escaping () -> Void) throws {
        guard hotkey == nil else {
            Log.hotkey.error("Registration failed: hotkey already registered")
            throw HotkeyError.alreadyRegistered
        }

        if !checkAccessibilityPermission() {
            Log.hotkey.error("Registration failed: accessibility permission denied")
            throw HotkeyError.accessibilityPermissionDenied
        }

        self.callback = callback

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (nextHandler, event, userData) -> OSStatus in
                guard let userData = userData else {
                    return OSStatus(eventNotHandledErr)
                }

                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()

                var hotkeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )

                if hotkeyID.id == 1 {
                    Log.hotkey.debug("Hotkey press detected (id=\(hotkeyID.id), signature=\(hotkeyID.signature))")
                    Task { @MainActor in
                        Log.hotkey.info("Invoking hotkey callback")
                        manager.callback?()
                    }
                } else {
                    Log.hotkey.debug("Ignored hotkey event with unknown id=\(hotkeyID.id)")
                }

                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard status == noErr else {
            throw HotkeyError.registrationFailed
        }

        var hotkeyID = EventHotKeyID(signature: OSType(0x504C4259), id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkey
        )

        guard registerStatus == noErr else {
            Log.hotkey.error("RegisterEventHotKey failed with status \(registerStatus)")
            if let handler = eventHandler {
                RemoveEventHandler(handler)
                eventHandler = nil
            }
            throw HotkeyError.registrationFailed
        }

        Log.hotkey.info("Registered hotkey: keyCode=\(keyCode), modifiers=\(modifiers)")
    }

    func unregister() {
        if let hotkey = hotkey {
            UnregisterEventHotKey(hotkey)
            self.hotkey = nil
        }

        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }

        callback = nil
        Log.hotkey.info("Unregistered hotkey")
    }

    private func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    deinit {
        Task { @MainActor in
            self.unregister()
        }
    }
}

extension GlobalHotkeyManager {
    static let optionShiftSpace: (keyCode: UInt32, modifiers: UInt32) = (
        keyCode: 49,
        modifiers: UInt32(optionKey | shiftKey)
    )

    /// Parses a shortcut string like "Option+Shift+Space" into Carbon keyCode and modifiers.
    /// Returns nil if the key cannot be mapped.
    static func parse(shortcut: String) -> (keyCode: UInt32, modifiers: UInt32)? {
        let parts = shortcut.split(separator: "+").map { String($0) }
        guard parts.count >= 2 else { return nil }

        var modifiers: UInt32 = 0
        var keyPart: String?

        for part in parts {
            switch part {
            case "Control": modifiers |= UInt32(controlKey)
            case "Option": modifiers |= UInt32(optionKey)
            case "Shift": modifiers |= UInt32(shiftKey)
            case "Command": modifiers |= UInt32(cmdKey)
            default: keyPart = part
            }
        }

        guard let key = keyPart, let keyCode = carbonKeyCode(for: key) else { return nil }
        return (keyCode: keyCode, modifiers: modifiers)
    }

    private static func carbonKeyCode(for key: String) -> UInt32? {
        switch key {
        case "Space": return 49
        case "Return": return 36
        case "Tab": return 48
        case "Delete": return 51
        case "Escape": return 53
        case "Up": return 126
        case "Down": return 125
        case "Left": return 123
        case "Right": return 124
        case "A": return 0
        case "B": return 11
        case "C": return 8
        case "D": return 2
        case "E": return 14
        case "F": return 3
        case "G": return 5
        case "H": return 4
        case "I": return 34
        case "J": return 38
        case "K": return 40
        case "L": return 37
        case "M": return 46
        case "N": return 45
        case "O": return 31
        case "P": return 35
        case "Q": return 12
        case "R": return 15
        case "S": return 1
        case "T": return 17
        case "U": return 32
        case "V": return 9
        case "W": return 13
        case "X": return 7
        case "Y": return 16
        case "Z": return 6
        case "0": return 29
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        case "5": return 23
        case "6": return 22
        case "7": return 26
        case "8": return 28
        case "9": return 25
        case "-": return 27
        case "=": return 24
        case "[": return 33
        case "]": return 30
        case "\\": return 42
        case ";": return 41
        case "'": return 39
        case ",": return 43
        case ".": return 47
        case "/": return 44
        case "`": return 50
        default: return nil
        }
    }
}

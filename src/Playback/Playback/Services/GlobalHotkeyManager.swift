// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import Carbon

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
            throw HotkeyError.alreadyRegistered
        }

        if !checkAccessibilityPermission() {
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
                    Task { @MainActor in
                        manager.callback?()
                    }
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
            if let handler = eventHandler {
                RemoveEventHandler(handler)
                eventHandler = nil
            }
            throw HotkeyError.registrationFailed
        }

        print("[GlobalHotkey] Registered hotkey: keyCode=\(keyCode), modifiers=\(modifiers)")
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
        print("[GlobalHotkey] Unregistered hotkey")
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
}

// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import SwiftUI
import AppKit
import Carbon

struct HotkeyRecorderView: View {
    @Binding var shortcut: String
    @State private var isRecording = false
    @State private var hasConflict = false
    @FocusState private var isFocused: Bool

    let onShortcutChanged: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if isRecording {
                    Text("Press keys...")
                        .foregroundColor(.secondary)
                        .frame(width: 200, height: 32)
                } else {
                    Text(shortcut)
                        .frame(width: 200, height: 32)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.blue : Color.gray.opacity(0.3), lineWidth: isRecording ? 2 : 1)
            )
            .cornerRadius(6)
            .contentShape(Rectangle())
            .onTapGesture {
                startRecording()
            }
            .focusable()
            .focused($isFocused)
            .onKeyPress { keyPress in
                if isRecording {
                    return handleKeyPress(keyPress)
                }
                return .ignored
            }

            if hasConflict {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .help("This shortcut may conflict with system shortcuts")
            }

            if shortcut != "Option+Shift+Space" {
                Button {
                    resetToDefault()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reset to default")
            }
        }
    }

    private func startRecording() {
        isRecording = true
        isFocused = true
    }

    private func stopRecording() {
        isRecording = false
        isFocused = false
    }

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        guard isRecording else { return .ignored }

        let modifiers = keyPress.modifiers
        let key = keyPress.key

        if modifiers.isEmpty && key == .escape {
            stopRecording()
            return .handled
        }

        if modifiers.isEmpty {
            return .ignored
        }

        var modifierStrings: [String] = []
        if modifiers.contains(.control) { modifierStrings.append("Control") }
        if modifiers.contains(.option) { modifierStrings.append("Option") }
        if modifiers.contains(.shift) { modifierStrings.append("Shift") }
        if modifiers.contains(.command) { modifierStrings.append("Command") }

        let keyString = formatKey(key)
        guard !keyString.isEmpty else { return .ignored }

        let newShortcut = modifierStrings.joined(separator: "+") + "+" + keyString

        hasConflict = checkForConflict(modifiers: modifiers, keyString: keyString)

        shortcut = newShortcut
        onShortcutChanged(newShortcut)
        stopRecording()

        return .handled
    }

    private func formatKey(_ key: KeyEquivalent) -> String {
        switch key.character.lowercased() {
        case " ": return "Space"
        case "\t": return "Tab"
        case "\r": return "Return"
        case "\u{7f}": return "Delete"
        case let c where c.unicodeScalars.first?.value == 63232: return "Up"
        case let c where c.unicodeScalars.first?.value == 63233: return "Down"
        case let c where c.unicodeScalars.first?.value == 63234: return "Left"
        case let c where c.unicodeScalars.first?.value == 63235: return "Right"
        default:
            return key.character.uppercased()
        }
    }

    private func checkForConflict(modifiers: SwiftUI.EventModifiers, keyString: String) -> Bool {
        let commonConflicts: [(modifiers: SwiftUI.EventModifiers, key: String)] = [
            (.command, "Q"),
            (.command, "W"),
            (.command, "H"),
            (.command, "M"),
            (.command, "Tab"),
            ([.command, .shift], "Q"),
        ]

        for conflict in commonConflicts {
            if modifiers == conflict.modifiers && keyString == conflict.key {
                return true
            }
        }

        return false
    }

    private func resetToDefault() {
        shortcut = "Option+Shift+Space"
        hasConflict = false
        onShortcutChanged("Option+Shift+Space")
    }
}

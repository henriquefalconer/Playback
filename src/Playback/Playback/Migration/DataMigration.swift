// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import AppKit
import CryptoKit
import os

/// A step of migration progress. `fraction` is nil while indeterminate.
struct MigrationProgress {
    let fraction: Double?
    let label: String
}

/// A one-time, at-launch upgrade of some part of the on-disk data. Concrete
/// migrations (e.g. the OCR search index) conform and are registered with
/// `MigrationCoordinator` — the generic dialog, key loading, and Open-Playback
/// gating are shared, so a new migration only supplies its own detection + work.
protocol DataMigration {
    /// Stable identifier, for logs.
    var id: String { get }
    /// True when this migration still needs to run against the database at `dbPath`.
    func isPending(dbPath: String) -> Bool
    /// Perform the migration. `key` is the OCR index key; report progress via
    /// `progress` (0…1, or nil for indeterminate). Failures must be logged and
    /// leave the data in a retryable state.
    func run(dbPath: String, key: SymmetricKey, progress: @escaping (MigrationProgress) -> Void)
}

/// Runs any pending data migrations at launch behind a shared native dialog, shown
/// *instead of* the timeline. The timeline, recording and OCR stay off until the
/// user clicks **Open Playback**.
@MainActor
enum MigrationCoordinator {
    /// The registered migrations, run in order. Add new ones here.
    static let migrations: [DataMigration] = [SearchIndexMigration()]

    static func runIfNeeded(immediate: @escaping () -> Void, afterMigration: @escaping () -> Void) {
        let dbPath = Paths.databasePath.path
        let pending = migrations.filter { $0.isPending(dbPath: dbPath) }
        guard !pending.isEmpty else {
            immediate()
            return
        }

        let dialog = MigrationProgressWindow(onOpen: afterMigration)
        dialog.present()

        DispatchQueue.global(qos: .userInitiated).async {
            let key = SearchCrypto.loadOrCreateKey()
            for migration in pending {
                Log.search.notice("Running data migration: \(migration.id, privacy: .public)")
                migration.run(dbPath: dbPath, key: key) { progress in
                    DispatchQueue.main.async { dialog.update(progress) }
                }
            }
            DispatchQueue.main.async { dialog.showCompleted() }
        }
    }
}

/// A non-dismissable, alert-styled window that shows migration progress (a native
/// determinate bar, indeterminate for open-ended steps) and then a borderless
/// **Open Playback** button that reveals the timeline. Fully generic — its copy
/// never names a specific subsystem.
@MainActor
final class MigrationProgressWindow {
    /// Retains the live dialog so its window and the button's target aren't
    /// deallocated when the coordinator returns — otherwise Open Playback is dead.
    private static var presented: MigrationProgressWindow?

    private let window: NSWindow
    private let heading: NSTextField
    private let bar: NSProgressIndicator
    private let status: NSTextField
    private let openButton: NSButton
    private let onOpen: () -> Void

    /// Anchor for the dynamic time estimate — first meaningful progress point.
    private var etaAnchorTime: Date?
    private var etaAnchorFraction: Double = 0

    init(onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
        let width: CGFloat = 460, height: CGFloat = 168
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .modalPanel
        window.center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let icon = NSImageView(frame: NSRect(x: 24, y: height - 24 - 64, width: 64, height: 64))
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        content.addSubview(icon)

        let textX: CGFloat = 104, textW = width - textX - 24

        heading = NSTextField(labelWithString: "Migrating your data…")
        heading.font = .boldSystemFont(ofSize: 13)
        heading.frame = NSRect(x: textX, y: height - 48, width: textW, height: 18)
        content.addSubview(heading)

        let subhead = NSTextField(labelWithString: "Your data is being migrated.")
        subhead.font = .systemFont(ofSize: 11)
        subhead.textColor = .secondaryLabelColor
        subhead.frame = NSRect(x: textX, y: height - 68, width: textW, height: 16)
        content.addSubview(subhead)

        bar = NSProgressIndicator(frame: NSRect(x: textX, y: 62, width: textW, height: 18))
        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.doubleValue = 0
        content.addSubview(bar)

        status = NSTextField(labelWithString: "Migrating your data…")
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.frame = NSRect(x: textX, y: 42, width: textW, height: 16)
        content.addSubview(status)

        openButton = NSButton(title: "Open Playback", target: nil, action: nil)
        openButton.isBordered = false
        openButton.focusRingType = .none
        openButton.attributedTitle = NSAttributedString(
            string: "Open Playback",
            attributes: [.foregroundColor: NSColor.controlAccentColor,
                         .font: NSFont.systemFont(ofSize: 13, weight: .semibold)]
        )
        openButton.keyEquivalent = "\r"
        openButton.sizeToFit()
        openButton.setFrameOrigin(NSPoint(x: width - 24 - openButton.frame.width, y: 14))
        openButton.isHidden = true
        content.addSubview(openButton)

        window.contentView = content
        openButton.target = self
        openButton.action = #selector(openTapped)
    }

    func present() {
        Self.presented = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(_ progress: MigrationProgress) {
        if let fraction = progress.fraction {
            if bar.isIndeterminate {
                bar.stopAnimation(nil)
                bar.isIndeterminate = false
            }
            bar.doubleValue = fraction
            status.stringValue = progress.label + estimate(for: fraction)
        } else {
            if !bar.isIndeterminate {
                bar.isIndeterminate = true
                bar.startAnimation(nil)
            }
            status.stringValue = progress.label + " (almost done)"
        }
    }

    /// Switch to the finished state: full bar and the Open Playback button.
    func showCompleted() {
        bar.stopAnimation(nil)
        bar.isIndeterminate = false
        bar.doubleValue = bar.maxValue
        heading.stringValue = "Migration complete"
        status.stringValue = "Your data has been migrated."
        openButton.isHidden = false
    }

    /// A parenthetical time estimate from the rate since the first meaningful
    /// progress point, so it excludes any keychain-wait at the start.
    private func estimate(for fraction: Double) -> String {
        guard fraction > 0.02, fraction < 0.999 else { return "" }
        if etaAnchorTime == nil {
            etaAnchorTime = Date()
            etaAnchorFraction = fraction
            return ""
        }
        guard let anchor = etaAnchorTime, fraction > etaAnchorFraction else { return "" }
        let elapsed = Date().timeIntervalSince(anchor)
        let rate = (fraction - etaAnchorFraction) / elapsed
        guard rate > 0, elapsed > 0.5 else { return "" }
        let remaining = (1 - fraction) / rate
        if remaining < 12 { return " (almost done)" }
        if remaining < 90 { return " (about \(Int((remaining / 10).rounded()) * 10) sec remaining)" }
        return " (about \(Int((remaining / 60).rounded())) min remaining)"
    }

    @objc private func openTapped() {
        bar.stopAnimation(nil)
        window.orderOut(nil)
        window.close()
        onOpen()
        Self.presented = nil
    }
}

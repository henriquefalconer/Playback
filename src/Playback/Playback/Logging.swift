import os

enum Log {
    static let recording   = Logger(subsystem: "com.falconer.Playback", category: "Recording")
    static let processing  = Logger(subsystem: "com.falconer.Playback", category: "Processing")
    static let playback    = Logger(subsystem: "com.falconer.Playback", category: "Playback")
    static let timeline    = Logger(subsystem: "com.falconer.Playback", category: "Timeline")
    static let ui          = Logger(subsystem: "com.falconer.Playback", category: "UI")
    static let menuBar     = Logger(subsystem: "com.falconer.Playback", category: "MenuBar")
    static let hotkey      = Logger(subsystem: "com.falconer.Playback", category: "Hotkey")
    static let config      = Logger(subsystem: "com.falconer.Playback", category: "Config")
    static let system      = Logger(subsystem: "com.falconer.Playback", category: "System")
    static let session     = Logger(subsystem: "com.falconer.Playback", category: "Session")
    static let settings    = Logger(subsystem: "com.falconer.Playback", category: "Settings")
    static let datepicker  = Logger(subsystem: "com.falconer.Playback", category: "DatePicker")
    static let search      = Logger(subsystem: "com.falconer.Playback", category: "Search")
}

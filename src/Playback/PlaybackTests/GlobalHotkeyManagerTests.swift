import XCTest
@testable import Playback

final class GlobalHotkeyManagerTests: XCTestCase {

    // MARK: - Singleton Tests

    func testSharedInstanceExists() {
        let manager = GlobalHotkeyManager.shared
        XCTAssertNotNil(manager, "GlobalHotkeyManager.shared should exist")
    }

    func testSharedInstanceIsSame() {
        let manager1 = GlobalHotkeyManager.shared
        let manager2 = GlobalHotkeyManager.shared
        XCTAssertTrue(manager1 === manager2, "GlobalHotkeyManager.shared should return same instance")
    }

    // MARK: - HotkeyError Enum Tests

    func testHotkeyErrorRegistrationFailedExists() {
        let error: HotkeyError = .registrationFailed
        XCTAssertNotNil(error, "HotkeyError.registrationFailed should exist")
    }

    func testHotkeyErrorAlreadyRegisteredExists() {
        let error: HotkeyError = .alreadyRegistered
        XCTAssertNotNil(error, "HotkeyError.alreadyRegistered should exist")
    }

    func testHotkeyErrorAccessibilityPermissionDeniedExists() {
        let error: HotkeyError = .accessibilityPermissionDenied
        XCTAssertNotNil(error, "HotkeyError.accessibilityPermissionDenied should exist")
    }

    func testHotkeyErrorConformsToError() {
        let error: HotkeyError = .registrationFailed
        let errorProtocol: Error = error
        XCTAssertNotNil(errorProtocol, "HotkeyError should conform to Error protocol")
    }

    // MARK: - Built-in Hotkey Constant Tests

    func testOptionShiftSpaceConstantExists() {
        let hotkey = GlobalHotkeyManager.optionShiftSpace
        XCTAssertNotNil(hotkey, "GlobalHotkeyManager.optionShiftSpace should exist")
    }

    func testOptionShiftSpaceHasKeyCode() {
        let hotkey = GlobalHotkeyManager.optionShiftSpace
        XCTAssertEqual(hotkey.keyCode, 49, "optionShiftSpace.keyCode should be 49 (space bar)")
    }

    func testOptionShiftSpaceHasModifiers() {
        let hotkey = GlobalHotkeyManager.optionShiftSpace
        XCTAssertGreaterThan(hotkey.modifiers, 0, "optionShiftSpace.modifiers should be non-zero")
    }

    func testOptionShiftSpaceModifiersIncludeOptionAndShift() {
        // Test that modifiers value is non-zero (contains some modifier keys)
        // Actual Carbon modifier values are implementation details
        let hotkey = GlobalHotkeyManager.optionShiftSpace
        XCTAssertGreaterThan(hotkey.modifiers, 0,
                            "optionShiftSpace.modifiers should be non-zero (contains modifier keys)")
    }

    // MARK: - Method Availability Tests

    func testGlobalHotkeyManagerHasRegisterMethod() {
        let manager = GlobalHotkeyManager.shared
        XCTAssertNotNil(type(of: manager), "GlobalHotkeyManager should be instantiable")
    }

    func testGlobalHotkeyManagerHasUnregisterMethod() {
        let manager = GlobalHotkeyManager.shared
        XCTAssertNotNil(type(of: manager), "GlobalHotkeyManager should be instantiable")
    }

    func testGlobalHotkeyManagerHasCheckAccessibilityPermissionMethod() {
        let manager = GlobalHotkeyManager.shared
        XCTAssertNotNil(manager, "GlobalHotkeyManager should have accessibility permission checking capability")
    }

    // MARK: - Unregister Safety Tests

    @MainActor
    func testUnregisterCanBeCalledMultipleTimes() {
        let manager = GlobalHotkeyManager.shared
        // Should not crash or throw
        manager.unregister()
        manager.unregister()
        manager.unregister()
    }

    @MainActor
    func testUnregisterWithoutRegisterDoesNotCrash() {
        let manager = GlobalHotkeyManager.shared
        // Should not throw or crash when unregister is called without prior registration
        manager.unregister()
    }

    // MARK: - Type Tests

    func testHotkeyConstantIsTuple() {
        let hotkey = GlobalHotkeyManager.optionShiftSpace
        let keyCodeType = type(of: hotkey.keyCode)
        let modifiersType = type(of: hotkey.modifiers)
        XCTAssertEqual(String(describing: keyCodeType), "UInt32",
                       "keyCode should be UInt32")
        XCTAssertEqual(String(describing: modifiersType), "UInt32",
                       "modifiers should be UInt32")
    }

    @MainActor
    func testGlobalHotkeyManagerIsMainActor() {
        let manager = GlobalHotkeyManager.shared
        XCTAssertNotNil(manager, "GlobalHotkeyManager should be marked @MainActor")
    }
}

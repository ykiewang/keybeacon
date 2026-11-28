// Copyright (c) 2026 The TOTEM ZMK Contributors
// SPDX-License-Identifier: MIT

import AppKit
import Carbon
import Carbon.HIToolbox

final class HotkeyRegistrar {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var keyCode: UInt32 = 0
    private var modifiers: UInt32 = 0
    private var handler: (() -> Void)?

    func register(modifiers: UInt32, keyCode: UInt32, handler: @escaping () -> Void) {
        unregister()
        guard keyCode != 0 else { return }
        self.modifiers = modifiers
        self.keyCode = keyCode
        self.handler = handler

        var hotKeyID = EventHotKeyID(signature: OSType(0x4B42504D), id: 1)

        let status = RegisterEventHotKey(
            EventKeyboardShortcutKeyCode(keyCode),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        _ = hotKeyID
        guard status == noErr else {
            hotKeyRef = nil
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                       eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(typeEventHotKeyID),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if let userData {
                let registrar = Unmanaged<HotkeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
                registrar.handler?()
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        handler = nil
    }
}

private func EventKeyboardShortcutKeyCode(_ code: UInt32) -> UInt32 { code }

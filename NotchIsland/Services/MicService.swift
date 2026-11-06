import CoreAudio
import Foundation

/// Watches the default input device: whether any app is using the microphone
/// (a call, a meeting, dictation) and whether it is muted, and mutes it.
///
/// Muting uses the device's own mute switch when it has one. Many built-in
/// microphones don't, so then the input volume is set to zero and restored
/// on unmute. Nothing is recorded; the app never opens the microphone.
@MainActor
final class MicService: ObservableObject {
    @Published private(set) var isInUse = false
    @Published private(set) var isMuted = false
    /// False when the device offers neither a mute switch nor an input volume.
    @Published private(set) var canMute = true

    private static let savedVolumesKey = "micSavedVolumes"
    /// Volume restored when nothing was saved, e.g. the mic was already at zero.
    private static let fallbackVolume: Float32 = 0.8
    /// Element 0 is the main control; 1... are individual channels.
    private static let elements: [UInt32] = [0, 1, 2, 3, 4]

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var listeners: [(id: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []
    private var muteElements: [UInt32] = []
    private var volumeElements: [UInt32] = []

    func start() {
        guard listeners.isEmpty else { return }
        addListener(AudioObjectID(kAudioObjectSystemObject),
                    AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                               mScope: kAudioObjectPropertyScopeGlobal,
                                               mElement: kAudioObjectPropertyElementMain)) { [weak self] in
            self?.bindDevice()
        }
        bindDevice()
    }

    // MARK: - Device

    private func bindDevice() {
        // Drop the old device's listeners, keep the system-level one (first).
        for listener in listeners.dropFirst() {
            var address = listener.address
            AudioObjectRemovePropertyListenerBlock(listener.id, &address, .main, listener.block)
        }
        listeners = Array(listeners.prefix(1))

        deviceID = Self.defaultInputDevice()
        guard deviceID != kAudioObjectUnknown else {
            muteElements = []
            volumeElements = []
            refresh()
            return
        }

        muteElements = Self.elements.filter { isSettable(kAudioDevicePropertyMute, $0) }
        volumeElements = Self.elements.filter { isSettable(kAudioDevicePropertyVolumeScalar, $0) }

        let refresh: () -> Void = { [weak self] in self?.refresh() }
        addListener(deviceID, Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere, scope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain), refresh)
        for element in muteElements { addListener(deviceID, Self.address(kAudioDevicePropertyMute, element: element), refresh) }
        for element in volumeElements { addListener(deviceID, Self.address(kAudioDevicePropertyVolumeScalar, element: element), refresh) }
        self.refresh()
    }

    private func refresh() {
        canMute = !muteElements.isEmpty || !volumeElements.isEmpty
        isInUse = deviceID != kAudioObjectUnknown && Self.uint32(deviceID, Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere, scope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain)) == 1
        if !muteElements.isEmpty {
            isMuted = muteElements.allSatisfy { Self.uint32(deviceID, Self.address(kAudioDevicePropertyMute, element: $0)) == 1 }
        } else if !volumeElements.isEmpty {
            isMuted = volumeElements.allSatisfy { (Self.float(deviceID, Self.address(kAudioDevicePropertyVolumeScalar, element: $0)) ?? 1) < 0.001 }
        } else {
            isMuted = false
        }
    }

    // MARK: - Muting

    func toggleMute() { setMuted(!isMuted) }

    func setMuted(_ mute: Bool) {
        guard canMute else { return }
        if !muteElements.isEmpty {
            for element in muteElements {
                Self.set(deviceID, Self.address(kAudioDevicePropertyMute, element: element), UInt32(mute ? 1 : 0))
            }
        } else if mute {
            var saved: [String: Double] = [:]
            for element in volumeElements {
                let address = Self.address(kAudioDevicePropertyVolumeScalar, element: element)
                if let volume = Self.float(deviceID, address), volume > 0.001 { saved["\(element)"] = Double(volume) }
                Self.set(deviceID, address, Float32(0))
            }
            // Keep the first save if already at zero, so a restart can still restore it.
            if !saved.isEmpty { UserDefaults.standard.set(saved, forKey: Self.savedVolumesKey) }
        } else {
            let saved = UserDefaults.standard.dictionary(forKey: Self.savedVolumesKey) as? [String: Double] ?? [:]
            for element in volumeElements {
                let volume = saved["\(element)"].map { Float32($0) } ?? Self.fallbackVolume
                Self.set(deviceID, Self.address(kAudioDevicePropertyVolumeScalar, element: element), volume)
            }
            UserDefaults.standard.removeObject(forKey: Self.savedVolumesKey)
        }
        refresh()
    }

    // MARK: - CoreAudio helpers

    private func addListener(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress, _ handler: @escaping () -> Void) {
        var address = address
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in handler() }
        }
        guard AudioObjectAddPropertyListenerBlock(id, &address, .main, block) == noErr else { return }
        listeners.append((id, address, block))
    }

    private func isSettable(_ selector: AudioObjectPropertySelector, _ element: UInt32) -> Bool {
        var address = Self.address(selector, element: element)
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr && settable.boolValue
    }

    private nonisolated static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeInput,
        element: UInt32
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private nonisolated static func defaultInputDevice() -> AudioObjectID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr
        else { return AudioObjectID(kAudioObjectUnknown) }
        return device
    }

    private nonisolated static func uint32(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> UInt32? {
        var address = address
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private nonisolated static func float(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Float32? {
        var address = address
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private nonisolated static func set<T>(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: T) {
        var address = address
        var value = value
        AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value)
    }
}

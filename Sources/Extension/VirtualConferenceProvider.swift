import EventKit
import AppKit

final class VirtualConferenceProvider: EKVirtualConferenceProvider {
    override func fetchAvailableRoomTypes() async throws -> [EKVirtualConferenceRoomTypeDescriptor] {
        [EKVirtualConferenceRoomTypeDescriptor(title: "Google Meet", identifier: "google-meet-new")]
    }
    override func fetchVirtualConference(identifier: EKVirtualConferenceRoomTypeIdentifier) async throws -> EKVirtualConferenceDescriptor {
        guard identifier == "google-meet-new" else { throw MeetError("Unknown conference type.") }
        let bridge = try BridgeListener()
        let callback = try await bridge.start()
        defer { bridge.cancel() }
        let appURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard appURL.pathExtension == "app" else { throw MeetError("Install Calendar Meet in Applications and reopen Calendar.") }
        let config = NSWorkspace.OpenConfiguration(); config.activates = false
        // Do not await Launch Services: it may defer URL delivery beyond the
        // conference deadline. The response listener supplies the bounded wait.
        NSWorkspace.shared.open([BridgeRequest.url(callback: callback)], withApplicationAt: appURL, configuration: config) { _, error in
            if error != nil { bridge.cancel() }
        }
        let url = try await bridge.response().result()
        return EKVirtualConferenceDescriptor(title: "Google Meet", urlDescriptors: [
            EKVirtualConferenceURLDescriptor(title: "Join Google Meet", url: url)
        ], conferenceDetails: "Join with Google Meet: \(url.absoluteString)")
    }
}

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
        return Self.conferenceDescriptor(url: url)
    }

    // Apple's single-join-option example leaves titles nil. Titles describe
    // rooms/alternate URLs; they are not a public API for the action button label.
    static func conferenceDescriptor(url: URL) -> EKVirtualConferenceDescriptor {
        EKVirtualConferenceDescriptor(title: nil, urlDescriptors: [
            EKVirtualConferenceURLDescriptor(title: nil, url: url)
        ], conferenceDetails: nil)
    }
}

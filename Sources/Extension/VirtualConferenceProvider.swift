import EventKit

final class VirtualConferenceProvider: EKVirtualConferenceProvider {
    override func fetchAvailableRoomTypes() async throws -> [EKVirtualConferenceRoomTypeDescriptor] {
        [EKVirtualConferenceRoomTypeDescriptor(title: "Google Meet", identifier: "google-meet-new")]
    }
    override func fetchVirtualConference(identifier: EKVirtualConferenceRoomTypeIdentifier) async throws -> EKVirtualConferenceDescriptor {
        guard identifier == "google-meet-new" else { throw MeetError("Unknown conference type.") }
        let url = try await ConferenceService.shared.create()
        return EKVirtualConferenceDescriptor(title: "Google Meet", urlDescriptors: [
            EKVirtualConferenceURLDescriptor(title: "Join Google Meet", url: url)
        ], conferenceDetails: "Join with Google Meet: \(url.absoluteString)")
    }
}

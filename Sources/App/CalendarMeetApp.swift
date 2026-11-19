import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct CalendarMeetApp: App {
    @StateObject private var model = SetupModel()
    var body: some Scene {
        WindowGroup {
            SetupView(model: model).frame(width: 520).fixedSize(horizontal: false, vertical: true)
        }.windowResizability(.contentSize)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

@MainActor
final class SetupModel: ObservableObject {
    @Published var client: OAuthClient?
    @Published var connected = false
    @Published var busy = false
    @Published var message = ""
    @Published var meeting: URL?
    private var loginTask: Task<Void, Never>?
    init() {
        do { if let credential = try Vault.load() { client = credential.client; connected = true } }
        catch { if !Vault.isPreview { message = error.localizedDescription } }
        if client == nil, let url = Bundle.main.url(forResource: "GoogleOAuthClient", withExtension: "json") {
            do { client = try OAuthClient.parse(Data(contentsOf: url)) }
            catch { message = error.localizedDescription }
        }
    }
    func importClient() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.message = "Choose the Desktop app OAuth JSON downloaded from Google Cloud."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { client = try OAuthClient.parse(Data(contentsOf: url)); message = "Google client imported. Connect your account next." }
        catch { message = error.localizedDescription }
    }
    func connect() {
        guard let client, !busy else { return }
        busy = true; message = "Finish Google sign-in in your browser."
        loginTask = Task {
            var server: Loopback?
            defer { server?.cancel(); busy = false; loginTask = nil }
            do {
                try Vault.requireSigned()
                let verifier = try OAuth.random(); let state = try OAuth.random()
                let callback = try Loopback(); server = callback
                let redirect = try await callback.start()
                // Arm the callback before opening the browser, including very fast cached consent.
                let wait = Task { try await callback.code(state: state) }
                defer { wait.cancel() }
                await Task.yield()
                guard NSWorkspace.shared.open(OAuth.authorizationURL(client: client, redirect: redirect, verifier: verifier, state: state)) else {
                    throw MeetError("Could not open your browser.")
                }
                let code = try await withTaskCancellationHandler { try await wait.value } onCancel: { callback.cancel() }
                try Task.checkCancellation()
                let credential = try await GoogleAPI().exchange(code: code, client: client, redirect: redirect, verifier: verifier)
                try Task.checkCancellation()
                try Vault.save(credential)
                connected = true; meeting = nil
                message = "Connected. In Calendar, select Google Meet under Add Location or Video Call."
            } catch is CancellationError { message = "Sign-in cancelled." }
            catch { message = error.localizedDescription }
        }
    }
    func cancel() { loginTask?.cancel() }
    func testMeeting() {
        guard !busy else { return }; busy = true; meeting = nil
        Task {
            defer { busy = false }
            do { meeting = try await ConferenceService.shared.create(); message = "A real test meeting was created. You can open or copy its link." }
            catch { message = error.localizedDescription }
        }
    }
    func disconnect(revoke: Bool) {
        guard !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do {
                if revoke, let credential = try Vault.load() { try await GoogleAPI().revoke(credential.refreshToken) }
                try Vault.remove(); connected = false; meeting = nil
                message = revoke ? "Google access revoked and local login removed." : "Local login removed. Google access can also be removed in your Google Account."
            } catch { message = error.localizedDescription }
        }
    }
}

struct SetupView: View {
    @ObservedObject var model: SetupModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calendar Meet").font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("Google Meet, right inside Apple Calendar.").foregroundStyle(.secondary)
                }
            }
            if Vault.isPreview {
                Label("Unsigned developer preview", systemImage: "hammer.fill").font(.headline)
                Text("This build lets you inspect the app and Calendar extension. Google login requires a signed build with shared Keychain provisioning. Setup instructions are included with the source.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                Label(model.client == nil ? "1. Add your Google client" : "1. Google client ready", systemImage: model.client == nil ? "doc.badge.plus" : "checkmark.circle.fill")
                    .font(.headline)
                Text("One Desktop app client can be used by your whole team. Each person signs in with their own Google account.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Import Google client JSON…", action: model.importClient).disabled(model.busy || model.connected)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Label(model.connected ? "2. Google connected" : "2. Connect Google", systemImage: model.connected ? "checkmark.circle.fill" : "person.crop.circle")
                    .font(.headline)
                Text("Only permission to create and manage this app’s Meet spaces. No access to your calendar, contacts, microphone or camera.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button(model.connected ? "Reconnect Google" : "Connect Google", action: model.connect)
                        .buttonStyle(.borderedProminent).disabled(model.client == nil || model.busy || Vault.isPreview)
                    if model.busy { ProgressView().controlSize(.small) }
                    if model.busy && !model.connected { Button("Cancel", action: model.cancel) }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("3. Choose Google Meet in Calendar").font(.headline)
                Text("Move the app to Applications and open it once. Enable Calendar Meet in System Settings → General → Login Items & Extensions if requested, then reopen Calendar. Add an event and choose Google Meet in Add Location or Video Call.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Open Calendar") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) }
                    Button("Create test meeting", action: model.testMeeting).disabled(!model.connected || model.busy)
                }
            }
            if !model.message.isEmpty { Text(model.message).font(.callout).textSelection(.enabled).accessibilityIdentifier("status") }
            if let meeting = model.meeting {
                HStack {
                    Link(meeting.absoluteString, destination: meeting)
                    Button("Copy link") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(meeting.absoluteString, forType: .string) }
                }.font(.callout)
            }
            HStack {
                Link("Google setup guide", destination: URL(string: "https://github.com/mikkelrobin/apple-google-meet/blob/main/docs/SETUP.md")!)
                Spacer()
                if model.connected {
                    Menu("Disconnect") {
                        Button("Remove local login") { model.disconnect(revoke: false) }
                        Button("Revoke Google access and disconnect") { model.disconnect(revoke: true) }
                    }.disabled(model.busy)
                }
                Text("v0.1.0").foregroundStyle(.tertiary)
            }.font(.caption)
        }.padding(30)
    }
}

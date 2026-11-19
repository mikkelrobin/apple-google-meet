import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ServiceManagement

@main
struct CalendarMeetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = SetupModel()
    private var item: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let icon = NSImage(contentsOf: Bundle.main.url(forResource: "AppIcon", withExtension: "icns")!)
            icon?.size = NSSize(width: 19, height: 19)
            button.image = icon
            button.toolTip = "Calendar Meet"
            button.target = self; button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: SetupView(model: model))
        model.configureLoginDefault()
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { model.handleBridge($0) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover(); return false
    }
    @objc private func clicked() {
        model.refreshLoginStatus()
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.performClose(nil)
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Calendar Meet", action: #selector(showPopover), keyEquivalent: "")
            menu.addItem(.separator())
            let quit = menu.addItem(withTitle: "Quit Calendar Meet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quit.target = NSApp
            menu.items.first?.target = self
            item.menu = menu; item.button?.performClick(nil); item.menu = nil
        } else if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }
    @objc private func showPopover() {
        guard let button = item?.button else { return }
        model.refreshLoginStatus()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class SetupModel: ObservableObject {
    @Published var client: OAuthClient?
    @Published var connected = false
    @Published var busy = false
    @Published var message = ""
    @Published var launchAtLogin = false
    func refreshLoginStatus() {
        launchAtLogin = [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
    }
    func configureLoginDefault() {
        if !UserDefaults.standard.bool(forKey: "launchAtLoginConfigured") {
            setLaunchAtLogin(true)
        } else { refreshLoginStatus() }
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            UserDefaults.standard.set(true, forKey: "launchAtLoginConfigured")
            message = SMAppService.mainApp.status == .requiresApproval
                ? "Allow Calendar Meet in System Settings → General → Login Items." : ""
        } catch { message = "Could not update Launch at Login. Try again after moving the app to Applications." }
        refreshLoginStatus()
    }
    var signingIn: Bool { loginTask != nil }
    private var loginTask: Task<Void, Never>?
    init() {
        do { if let credential = try Vault.load() { client = credential.client; connected = true } }
        catch { message = error.localizedDescription }
        if client == nil, let url = Bundle.main.url(forResource: "GoogleOAuthClient", withExtension: "json") {
            do { client = try OAuthClient.parse(Data(contentsOf: url)) }
            catch { message = error.localizedDescription }
        }
    }
    func importClient() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.message = "Choose your team’s Google sign-in configuration."
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
                connected = true
                message = ""
            } catch is CancellationError { message = "Sign-in cancelled." }
            catch { message = error.localizedDescription }
        }
    }
    func cancel() { loginTask?.cancel() }
    private var bridgeBusy = false
    private var handledCallbacks: [URL: Date] = [:]
    func handleBridge(_ url: URL) {
        let callback: URL
        do { callback = try BridgeRequest.callback(from: url) }
        catch { message = error.localizedDescription; return }
        handledCallbacks = handledCallbacks.filter { Date().timeIntervalSince($0.value) < 120 }
        guard handledCallbacks[callback] == nil else { return }
        handledCallbacks[callback] = Date()
        guard !bridgeBusy else {
            Task { try? await BridgeRequest.reply(BridgeReply(meetingURL: nil, error: "Another request is in progress. Try again."), to: callback) }
            return
        }
        bridgeBusy = true
        Task { @MainActor in
            defer { bridgeBusy = false }
            // Ignore delayed Launch Services requests after Calendar stopped waiting.
            guard await BridgeRequest.isWaiting(callback) else { return }
            let reply: BridgeReply
            if !connected {
                message = "Calendar reached the app successfully. Connect Google, then choose Google Meet in Calendar again."
                reply = BridgeReply(meetingURL: nil, error: "Open Calendar Meet and connect Google, then select Google Meet again.")
            } else if busy {
                reply = BridgeReply(meetingURL: nil, error: "Finish the current action in Calendar Meet, then try again.")
            } else {
                busy = true
                do {
                    let link = try await ConferenceService.shared.create()
                    reply = BridgeReply(meetingURL: link.absoluteString, error: nil)
                    message = ""
                } catch { reply = BridgeReply(meetingURL: nil, error: error.localizedDescription) }
                busy = false
            }
            do { try await BridgeRequest.reply(reply, to: callback) }
            catch { message = error.localizedDescription }
        }
    }
}

struct SetupView: View {
    @ObservedObject var model: SetupModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Calendar Meet").font(.system(size: 19, weight: .semibold, design: .rounded))
                    Label(model.connected ? "Google connected" : "Connect your Google account",
                          systemImage: model.connected ? "checkmark.circle.fill" : "person.crop.circle")
                        .font(.caption).foregroundStyle(model.connected ? .green : .secondary)
                }
            }
            if model.client == nil {
                Button("Set up Google sign-in…", action: model.importClient).disabled(model.busy)
            } else {
                Button(model.connected ? "Reconnect Google Account" : "Sign in with Google", action: model.connect)
                    .buttonStyle(.borderedProminent).disabled(model.busy)
            }
            if model.busy {
                HStack {
                    ProgressView().controlSize(.small)
                    if model.signingIn { Button("Cancel", action: model.cancel) }
                }
            }
            Divider()
            Toggle("Launch at Login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                .toggleStyle(.switch)
            if !model.message.isEmpty { Text(model.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }.padding(22).frame(width: 310)
    }
}

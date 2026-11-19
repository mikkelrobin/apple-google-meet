import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ServiceManagement
import Combine

@main
struct CalendarMeetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

// Decorative subviews must not intercept clicks intended for the status button.
final class StatusGlyphView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
final class ConnectionDotView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = SetupModel()
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private let connectionDot = ConnectionDotView()
    private var connectionSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: 36)
        if let button = item.button {
            let symbol = NSImage(systemSymbolName: "video", accessibilityDescription: nil)!
            symbol.isTemplate = true
            let icon = StatusGlyphView(image: symbol)
            icon.contentTintColor = .labelColor
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            icon.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(icon)
            connectionDot.translatesAutoresizingMaskIntoConstraints = false
            connectionDot.wantsLayer = true
            connectionDot.layer?.cornerRadius = 3.5
            button.addSubview(connectionDot)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
                icon.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 18), icon.heightAnchor.constraint(equalToConstant: 18),
                connectionDot.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 3),
                connectionDot.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                connectionDot.widthAnchor.constraint(equalToConstant: 7), connectionDot.heightAnchor.constraint(equalToConstant: 7)
            ])
            connectionSubscription = model.$connected.sink { [weak self] connected in
                self?.connectionDot.layer?.backgroundColor = (connected ? NSColor.systemGreen : NSColor.systemRed).cgColor
                let status = connected ? "Google connected" : "Google disconnected"
                self?.item.button?.toolTip = "Calendar Meet — " + status
                self?.item.button?.setAccessibilityLabel("Calendar Meet — " + status)
            }
            button.target = self; button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: SetupView(model: model))
        model.configureLoginDefault()
        model.startReconciliation()
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { url in
            if PendingConference.id(from: url) != nil { model.openPending(url); showPopover() }
            else { model.handleBridge(url) }
        }
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
        do { if let credential = try Vault.load() { client = credential.client; connected = credential.supportsCalendar
            if !connected { message = "Reconnect Google to enable Calendar access." } } }
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
    func signOut() {
        guard !busy else { return }
        busy = true
        let work = reconciliation
        work?.cancel()
        Task { @MainActor in
            // Wait for in-flight refresh/Calendar work before deleting credentials,
            // so a late refresh cannot silently sign the user back in.
            await work?.value
            defer { busy = false }
            do {
                try Vault.remove()
                pending.removeAll(); persistPending()
                resolved.removeAll()
                UserDefaults.standard.removeObject(forKey: "resolvedCalendarConferences")
                connected = false; message = ""
            } catch {
                message = error.localizedDescription
                startReconciliation()
            }
        }
    }

    private var pending: [PendingConference] = {
        guard let data = UserDefaults.standard.data(forKey: "pendingCalendarConferences") else { return [] }
        return ((try? JSONDecoder().decode([PendingConference].self, from: data)) ?? []).filter { PendingConference.validID($0.id) }
    }()
    private var resolved: [String: String] = UserDefaults.standard.dictionary(forKey: "resolvedCalendarConferences") as? [String: String] ?? [:]
    private var reconciliation: Task<Void, Never>?
    private func persistPending() {
        UserDefaults.standard.set(try? JSONEncoder().encode(pending), forKey: "pendingCalendarConferences")
    }
    func openPending(_ url: URL) {
        guard let id = PendingConference.id(from: url) else { return }
        if let text = resolved[id], let link = URL(string: text), link.scheme == "https", link.host == "meet.google.com" {
            NSWorkspace.shared.open(link)
        } else {
            message = "Save the event in your Google calendar and wait for sync. Meet is not ready yet."
            startReconciliation()
        }
    }
    func startReconciliation() {
        guard reconciliation == nil else { return }
        reconciliation = Task { @MainActor in
            defer { reconciliation = nil }
            var calendars: [CalendarEntry] = []
            var refreshedAt = Date.distantPast
            while !Task.isCancelled, !pending.isEmpty {
                if connected, !busy {
                    do {
                        let token = try await ConferenceService.shared.token()
                        let api = CalendarConferenceAPI()
                        if Date().timeIntervalSince(refreshedAt) > 300 {
                            calendars = try await api.calendars(token: token); refreshedAt = Date()
                            if calendars.isEmpty { message = "No writable Google calendar supports Meet for this account." }
                        }
                        // Work on a snapshot: incoming Calendar requests may append while awaiting HTTP.
                        for var request in pending {
                            do {
                            try Task.checkCancellation()
                            if Date().timeIntervalSince(request.createdAt) > 86400 {
                                pending.removeAll { $0.id == request.id }; persistPending()
                                message = "A Meet request expired. Choose Google Meet again on the saved Google Calendar event."
                                continue
                            }
                            let event: GoogleEvent
                            let calendarID: String
                            if let cid = request.calendarID, let eid = request.eventID {
                                calendarID = cid
                                event = try await api.event(calendarID: cid, eventID: eid, token: token)
                            } else {
                                var matches: [(String, GoogleEvent)] = []
                                for calendar in calendars {
                                    matches += try await api.matches(request, calendarID: calendar.id, token: token).map { (calendar.id, $0) }
                                }
                                guard matches.count <= 1 else {
                                    message = "This Meet request appears on multiple events. Remove it and choose Google Meet separately on each event."
                                    continue
                                }
                                guard let match = matches.first else { continue }
                                calendarID = match.0; event = match.1
                                request.calendarID = calendarID; request.eventID = event.id
                                if let index = pending.firstIndex(where: { $0.id == request.id }) { pending[index] = request; persistPending() }
                            }
                            if event.status == "cancelled" {
                                pending.removeAll { $0.id == request.id }; persistPending(); continue
                            }
                            let result: GoogleEvent
                            if event.conferenceData?.createRequest?.requestId == request.id {
                                result = event
                            } else {
                                // Re-fetch after discovery, then use If-Match to avoid racing user edits.
                                let latest = try await api.event(calendarID: calendarID, eventID: event.id, token: token)
                                guard latest.carries(request) else {
                                    pending.removeAll { $0.id == request.id }; persistPending(); continue
                                }
                                try Task.checkCancellation()
                                result = try await api.create(on: latest, calendarID: calendarID, pending: request, token: token)
                            }
                            if result.conferenceData?.createRequest?.status?.statusCode == "failure" {
                                throw MeetError("Google could not create this meeting. Remove the pending link and select Google Meet again.")
                            }
                            if let link = result.meetURL {
                                try Task.checkCancellation()
                                _ = try await api.finish(result, calendarID: calendarID, pending: request, token: token)
                                resolved[request.id] = link.absoluteString
                                if resolved.count > 100 { resolved = [request.id: link.absoluteString] }
                                UserDefaults.standard.set(resolved, forKey: "resolvedCalendarConferences")
                                pending.removeAll { $0.id == request.id }; persistPending()
                                message = pending.isEmpty ? "" : "Waiting for saved events to sync…"
                            }
                            } catch {
                                if error is GoogleAuthorizationError { connected = false }
                                if !(error is CancellationError) { message = error.localizedDescription }
                            }
                        }
                    } catch {
                        if error is GoogleAuthorizationError { connected = false }
                        if !(error is CancellationError) { message = error.localizedDescription }
                    }
                }
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }
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
                    guard pending.count < 16 else { throw MeetError("Too many unfinished requests. Save your Calendar events first.") }
                    let request = PendingConference.make()
                    pending.append(request)
                    persistPending()
                    reply = BridgeReply(meetingURL: request.url.absoluteString, error: nil)
                    message = "Save the event in your Google calendar. Meet will be added after sync."
                    startReconciliation()
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
                if model.connected {
                    Button("Sign Out", action: model.signOut).disabled(model.busy)
                }
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

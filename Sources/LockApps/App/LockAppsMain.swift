import AppKit
import ServiceManagement

@main
enum LockAppsMain {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--agent") {
            AgentCLI.run(args.count > i + 1 ? args[i + 1] : "status")
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // LSUIElement: starts as a menu-bar app; the Dock icon appears only while the window is open.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

/// `LockApps --agent status|register|unregister` — inspect or toggle the launchd agent from a shell
/// (run the binary inside the installed .app so SMAppService can find the embedded plist).
enum AgentCLI {
    static func run(_ command: String) {
        let agent = SMAppService.agent(plistName: AppSettings.agentPlistName)
        func describe(_ status: SMAppService.Status) -> String {
            switch status {
            case .enabled: return "enabled"
            case .notRegistered: return "notRegistered"
            case .requiresApproval: return "requiresApproval"
            case .notFound: return "notFound"
            @unknown default: return "unknown(\(status.rawValue))"
            }
        }
        do {
            switch command {
            case "register": try agent.register()
            case "unregister":
                let done = DispatchSemaphore(value: 0)
                var failure: Error?
                agent.unregister { error in failure = error; done.signal() }
                if done.wait(timeout: .now() + 15) == .timedOut { print("agent unregister timed out"); exit(1) }
                if let failure, (failure as NSError).code != kSMErrorJobNotFound { throw failure }
            case "status": break
            default:
                print("usage: LockApps --agent status|register|unregister")
                exit(2)
            }
            print("agent \(describe(agent.status))")
        } catch {
            print("agent \(command) failed: \(error.localizedDescription)")
            exit(1)
        }
    }
}

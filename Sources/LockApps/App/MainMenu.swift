import AppKit

/// Minimal main menu so ⌘C/⌘V/⌘Z work in text fields and ⌘Q / ⌘W behave.
@MainActor
enum MainMenuBuilder {
    static func build(openSettings: @escaping () -> Void, openWindow: @escaping () -> Void) -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "LockApps에 관하여", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title: "설정…", action: #selector(MenuTarget.openSettings), keyEquivalent: ",")
        settings.target = MenuTarget.shared
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "LockApps 가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "기타 가리기", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "모두 보기", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "LockApps 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "편집")
        editItem.submenu = edit
        edit.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "실행 복귀", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "오려두기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let window = NSMenu(title: "윈도우")
        windowItem.submenu = window
        let show = NSMenuItem(title: "LockApps 열기", action: #selector(MenuTarget.openWindow), keyEquivalent: "1")
        show.target = MenuTarget.shared
        window.addItem(show)
        window.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "확대/축소", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window

        MenuTarget.shared.openSettingsHandler = openSettings
        MenuTarget.shared.openWindowHandler = openWindow
        return main
    }
}

@MainActor
final class MenuTarget: NSObject {
    static let shared = MenuTarget()
    var openSettingsHandler: (() -> Void)?
    var openWindowHandler: (() -> Void)?

    @objc func openSettings() { openSettingsHandler?() }
    @objc func openWindow() { openWindowHandler?() }
}

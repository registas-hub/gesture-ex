import AppKit

/// `BrowserAction` 선택용 NSPopUpButton 채우기·읽기 헬퍼.
/// 17개 액션을 카테고리(Navigation/Tabs/Scroll/Page)로 청킹해 결정 비용을 낮춘다.
/// 항목 인식은 항상 `representedObject`로 하므로 root 인덱스가 separator·header로 어긋나도 안전하다.
enum BrowserActionPopup {

    /// popup의 menu를 BrowserAction 항목으로 채운다.
    /// - Parameters:
    ///   - popup: 채울 NSPopUpButton.
    ///   - includeDisabled: `disabled` 항목을 최상단에 노출할지 여부.
    ///       기본 매핑(SettingsWindow)에서는 true, 커스텀 등록(AddGesture)에서는 false.
    static func populate(_ popup: NSPopUpButton, includeDisabled: Bool) {
        guard let menu = popup.menu else { return }
        menu.removeAllItems()

        if includeDisabled {
            let disabledItem = NSMenuItem(
                title: BrowserAction.disabled.menuTitle,
                action: nil,
                keyEquivalent: ""
            )
            disabledItem.representedObject = BrowserAction.disabled
            menu.addItem(disabledItem)
        }

        // 첫 카테고리 앞 separator는 disabled 항목과 구분할 때만 필요
        var firstCategory = true

        for category in BrowserActionCategory.allCases {
            if includeDisabled || !firstCategory {
                menu.addItem(NSMenuItem.separator())
            }
            firstCategory = false

            let header = NSMenuItem(title: category.label, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for action in category.actions {
                let item = NSMenuItem(title: action.menuTitle, action: nil, keyEquivalent: "")
                item.representedObject = action
                item.indentationLevel = 1
                menu.addItem(item)
            }
        }

        // 호출자가 select(...)를 명시적으로 부르지 않더라도 popup이 항상 실제 BrowserAction을
        // 가리키도록 첫 representedObject 항목을 자동 선택한다.
        // 자동 선택이 없으면 includeDisabled=false 분기에서 첫 항목이 disabled 카테고리 헤더라
        // popup 타이틀이 "Navigation"으로 보이고 selectedAction(in:)이 nil을 반환해 Save가 silent fail.
        if let firstActionIdx = menu.items.firstIndex(where: { $0.representedObject is BrowserAction }) {
            popup.selectItem(at: firstActionIdx)
        }
    }

    /// representedObject가 매칭되는 메뉴 항목을 popup의 selectedItem으로 설정한다.
    /// 매칭이 없으면 popup 상태는 변경하지 않는다.
    static func select(_ action: BrowserAction, in popup: NSPopUpButton) {
        if let idx = popup.menu?.items.firstIndex(where: {
            ($0.representedObject as? BrowserAction) == action
        }) {
            popup.selectItem(at: idx)
        }
    }

    /// 현재 popup이 가리키는 BrowserAction을 representedObject에서 읽어온다.
    static func selectedAction(in popup: NSPopUpButton) -> BrowserAction? {
        popup.selectedItem?.representedObject as? BrowserAction
    }
}

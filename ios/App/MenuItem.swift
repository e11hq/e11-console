import UIKit

// One item of a page's ••• menu (a client's page, Client Assets, a folder…): Apple's own menu is made from these
// (ClientsPushedVC.items).
struct CornerMenuItem: Identifiable {
  let id = UUID()
  var title: String
  var symbol: String? = nil
  var destructive = false
  var inline = false                 // (its children shown in place, in their own section)
  var children: [CornerMenuItem] = []
  var run: (() -> Void)? = nil
}

// ---------- a screen shown, hidden or changed ----------
// (the old shared top buttons are gone — every page has Apple's own bar, Haris 2026-11-11; what's left: the shared + and
//  Apple's tab bar follow the screen on show)
extension Main {
  // (a tab change hides one screen and shows the next a moment apart: settled together)
  func updateCorner(animated: Bool = true) {
    if cornerPending { return }
    cornerPending = true
    DispatchQueue.main.async { self.cornerPending = false; self.updateCornerNow(animated: animated) }
  }
  func updateCornerNow(animated: Bool = true) {
    // (only once there's a screen of the app's own)
    guard homeIfMade != nil || myTasksIfMade != nil || inboxIfMade != nil || clientsListIfMade != nil || clientPageIfMade != nil || !taskPages.isEmpty || assetsCtl.isOpen || meCtl.isOpen else { return }
    for h in [homeIfMade, myTasksIfMade, inboxIfMade, clientsListIfMade, clientPageIfMade].compactMap({ $0 }) where !h.cornerShared { h.cornerShared = true; h.onCorner = { [weak self] in self?.updateCorner() } }
    fabFollow()   // (the shared +: SharedFab.swift)
    appleHomeBar(animated: false)
    if lockView != nil { return }
    AppleTabs.shared?.mirrorShown()
  }
}

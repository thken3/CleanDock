import CoreGraphics
import Testing
@testable import CleanDockCore

@Test func iconRectSmallTile() {
    // measured at tile size 17: tile frame 19×31, icon canvas 17×17 at +1, +7
    let r = TileGeometry.iconRect(tile: CGRect(x: -1752.775, y: 1133, width: 19, height: 31))
    #expect(abs(r.minX - -1751.775) < 0.001)
    #expect(r.minY == 1140)
    #expect(r.width == 17)
    #expect(r.height == 17)
}

@Test func iconRectLargeTile() {
    // measured at tile size 48: tile frame 52×68, icon canvas 48×48 at +2, +10
    let r = TileGeometry.iconRect(tile: CGRect(x: 100, y: 1096, width: 52, height: 68))
    #expect(r == CGRect(x: 102, y: 1106, width: 48, height: 48))
}

@Test func iconRectGrowingTile() {
    // measured during grow-in: tile frame 3.53×15.53
    let r = TileGeometry.iconRect(tile: CGRect(x: 0, y: 0, width: 3.53, height: 15.53))
    #expect(abs(r.width - 1.53) < 0.001)
    #expect(abs(r.midX - 1.765) < 0.001)
    #expect(abs(r.midY - 7.765) < 0.001)
}

@Test func screenLocalLeftOfPrimary() {
    // 3440×1440 display left of an 1800×1169 primary, bottoms aligned
    let r = TileGeometry.toScreenLocal(CGRect(x: -1751.775, y: 1140, width: 17, height: 17),
                                       screenFrame: CGRect(x: -3440, y: 0, width: 3440, height: 1440), primaryHeight: 1169)
    #expect(abs(r.minX - 1688.225) < 0.001)
    #expect(r.minY == 1411)
    #expect(r.size == CGSize(width: 17, height: 17))
}

@Test func screenLocalRightOfPrimary() {
    let r = TileGeometry.toScreenLocal(CGRect(x: 2000, y: 1100, width: 17, height: 17),
                                       screenFrame: CGRect(x: 1800, y: 0, width: 2560, height: 1169), primaryHeight: 1169)
    #expect(r.origin == CGPoint(x: 200, y: 1100))
}

@Test func screenLocalAbovePrimary() {
    // display above the primary: its top edge is at y = −1440 in Accessibility coordinates
    let r = TileGeometry.toScreenLocal(CGRect(x: 10, y: -40, width: 17, height: 17),
                                       screenFrame: CGRect(x: 0, y: 1169, width: 2560, height: 1440), primaryHeight: 1169)
    #expect(r.origin == CGPoint(x: 10, y: 1400))
}

@Test func accessibilityFrameFlipsAroundThePrimary() {
    #expect(TileGeometry.accessibilityFrame(CGRect(x: 0, y: 0, width: 1800, height: 1169), primaryHeight: 1169)
            == CGRect(x: 0, y: 0, width: 1800, height: 1169))
    // a display above the primary sits at negative y in Accessibility coordinates
    #expect(TileGeometry.accessibilityFrame(CGRect(x: 0, y: 1169, width: 2560, height: 1440), primaryHeight: 1169)
            == CGRect(x: 0, y: -1440, width: 2560, height: 1440))
    #expect(TileGeometry.accessibilityFrame(CGRect(x: -3440, y: 0, width: 3440, height: 1440), primaryHeight: 1169)
            == CGRect(x: -3440, y: -271, width: 3440, height: 1440))
}

private let primaryAX = CGRect(x: 0, y: 0, width: 1800, height: 1169)
private let upperAX = CGRect(x: 0, y: -1440, width: 2560, height: 1440)

@Test func stackedDisplaysPickTheOneThatReallyContainsTheDock() {
    // Dock at the bottom of the upper display; the primary is listed first and would win any inflated pass.
    #expect(TileGeometry.screenIndex(containing: CGPoint(x: 900, y: -30), screens: [primaryAX, upperAX], margin: 150) == 1)
    // Dock at the bottom of the primary
    #expect(TileGeometry.screenIndex(containing: CGPoint(x: 900, y: 1140), screens: [primaryAX, upperAX], margin: 150) == 0)
}

@Test func sideBySideDisplays() {
    let leftAX = CGRect(x: -3440, y: -271, width: 3440, height: 1440)
    #expect(TileGeometry.screenIndex(containing: CGPoint(x: -1700, y: 1140), screens: [primaryAX, leftAX], margin: 150) == 1)
    #expect(TileGeometry.screenIndex(containing: CGPoint(x: 900, y: 1140), screens: [primaryAX, leftAX], margin: 150) == 0)
}

@Test func anAutoHiddenDockBelowTheScreenIsStillFound() {
    #expect(TileGeometry.screenIndex(containing: CGPoint(x: 900, y: 1200), screens: [primaryAX, upperAX], margin: 150) == 0)
}

@Test func theInflatedPassTakesTheNearestCandidate() {
    let belowAX = CGRect(x: 0, y: 1200, width: 1800, height: 800)
    // 31 pt below the primary's bottom edge and 20 pt above the lower display's top edge
    #expect(TileGeometry.screenIndex(containing: CGPoint(x: 100, y: 1180), screens: [belowAX, primaryAX], margin: 150) == 1)
    #expect(TileGeometry.screenIndex(containing: CGPoint(x: 100, y: 1190), screens: [primaryAX, belowAX], margin: 150) == 1)
}

@Test func aPointFarFromEveryScreenHasNoScreen() {
    #expect(TileGeometry.screenIndex(containing: CGPoint(x: 5000, y: 5000), screens: [primaryAX, upperAX], margin: 150) == nil)
    #expect(TileGeometry.screenIndex(containing: CGPoint(x: 900, y: 1400), screens: [primaryAX], margin: 150) == nil)
    #expect(TileGeometry.screenIndex(containing: .zero, screens: [], margin: 150) == nil)
}

@Test func snappedToWholePixels() {
    #expect(TileGeometry.snapped(CGRect(x: 1688.225, y: 1411, width: 17, height: 17), scale: 1) == CGRect(x: 1688, y: 1411, width: 17, height: 17))
    #expect(TileGeometry.snapped(CGRect(x: 10.3, y: 5.26, width: 17, height: 17), scale: 2) == CGRect(x: 10.5, y: 5.5, width: 17, height: 17))
    #expect(TileGeometry.snapped(CGRect(x: 0, y: 0, width: 16.6, height: 16.6), scale: 1).size == CGSize(width: 17, height: 17))
}

@Test func restingSideIsTheMostCommon() {
    #expect(TileGeometry.restingSide([17, 17, 17, 9.2, 17]) == 17)
    #expect(TileGeometry.restingSide([17, 24.3, 31.8, 24.1, 17, 17]) == 17)
    #expect(TileGeometry.restingSide([]) == 0)
}

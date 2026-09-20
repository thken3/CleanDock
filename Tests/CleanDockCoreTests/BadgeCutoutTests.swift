import CoreGraphics
import Testing
@testable import CleanDockCore

@Test func noBadgeNoCutout() {
    #expect(BadgeCutout.rect(side: 17, label: "") == nil)
    #expect(BadgeCutout.rect(side: 0, label: "1") == nil)
}

@Test func oneCharacterBadge() {
    // measured at side 17: solid red spans x 9.8–16.8, y 0–7; the cutout adds the soft edge
    #expect(BadgeCutout.rect(side: 17, label: "1") == CGRect(x: 8, y: 0, width: 9, height: 8))
}

@Test func widerLabelsCutFurtherLeft() {
    #expect(BadgeCutout.rect(side: 17, label: "42") == CGRect(x: 6, y: 0, width: 11, height: 8))
    #expect(BadgeCutout.rect(side: 17, label: "130") == CGRect(x: 5, y: 0, width: 12, height: 8))
}

@Test func cutoutIsCappedAtThreeQuarters() {
    #expect(BadgeCutout.rect(side: 17, label: "99999") == CGRect(x: 5, y: 0, width: 12, height: 8))
}

@Test func scalesWithTheIcon() {
    #expect(BadgeCutout.rect(side: 64, label: "1") == CGRect(x: 32, y: 0, width: 32, height: 28))
}

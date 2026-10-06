import Foundation

@main
enum GeometryTests {
    static func main() {
        let notch = IslandScreenGeometry(screenWidth: 1470, safeAreaTop: 32,
            auxiliaryLeftWidth: 643, auxiliaryRightWidth: 643, menuBarHeight: 24)
        precondition(notch.hasNotch && notch.width == 184 && notch.height == 32)
        precondition(notch.restingOverlayWidth == notch.width)
        precondition(notch.restingOverlayHeight == notch.height)
        let fallback = IslandScreenGeometry(screenWidth: 1470, safeAreaTop: 32,
            auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 24)
        precondition(fallback.width == 184)
        let invalid = IslandScreenGeometry(screenWidth: 1470, safeAreaTop: 32,
            auxiliaryLeftWidth: 1000, auxiliaryRightWidth: 1000, menuBarHeight: 24)
        precondition(invalid.width == 184)
        let external = IslandScreenGeometry(screenWidth: 2560, safeAreaTop: 0,
            auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 24)
        precondition(!external.hasNotch && external.width == 80 && external.height == 24)
        precondition(external.restingOverlayWidth == 0 && external.restingOverlayHeight == 0)
        let smallMenu = IslandScreenGeometry(screenWidth: 2560, safeAreaTop: 0,
            auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 18)
        precondition(smallMenu.height == 18)
        print("Hub Island geometry: 5 cases plus resting menu-bar non-overlap passed")
    }
}

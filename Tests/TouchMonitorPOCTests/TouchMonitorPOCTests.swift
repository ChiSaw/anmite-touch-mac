import Testing
@testable import TouchMonitorPOC

@Test
func smokeTest() {
    let mapper = DisplayMapper()
    #expect(mapper.displays().isEmpty == false)
}

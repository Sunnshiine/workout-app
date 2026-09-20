import Testing

// Deliberately the banned shape. This file exists to make the `lint` job fail once, proving the new
// rule reaches CI and not only a local run, and is reverted in the commit straight after.
@Test func platformGuardRuleFiresOnAGuardedBody() {
    #if canImport(AppKit)
        #expect(1 + 1 == 2)
    #endif
}

import Foundation
import Testing
@testable import OmanStorage

private func makeTemporaryStore() -> KeychainAPIKeyStore {
    KeychainAPIKeyStore(service: "com.romanbitca.oman.tests.\(UUID().uuidString)", account: "test-account")
}

@Suite("Keychain API key store")
struct KeychainAPIKeyStoreTests {
    @Test func loadsNilWhenNothingIsStored() throws {
        let store = makeTemporaryStore()
        defer { try? store.deleteAPIKey() }

        #expect(try store.loadAPIKey() == nil)
    }

    @Test func savesUpdatesAndDeletes() throws {
        let store = makeTemporaryStore()
        defer { try? store.deleteAPIKey() }

        try store.saveAPIKey("first-test-value")
        #expect(try store.loadAPIKey() == "first-test-value")

        try store.saveAPIKey("second-test-value")
        #expect(try store.loadAPIKey() == "second-test-value")

        try store.deleteAPIKey()
        #expect(try store.loadAPIKey() == nil)
    }

    @Test func deletingAnAbsentKeyDoesNotThrow() throws {
        let store = makeTemporaryStore()

        try store.deleteAPIKey()
    }

    @Test func storesAreIsolatedByService() throws {
        let first = makeTemporaryStore()
        let second = makeTemporaryStore()
        defer {
            try? first.deleteAPIKey()
            try? second.deleteAPIKey()
        }

        try first.saveAPIKey("value-for-first")

        #expect(try second.loadAPIKey() == nil)
        #expect(try first.loadAPIKey() == "value-for-first")
    }

    @Test func errorDescriptionNamesTheStatusOnly() {
        let description = KeychainStoreError.unexpectedStatus(errSecAuthFailed).errorDescription

        #expect(description?.contains("\(errSecAuthFailed)") == true)
    }
}

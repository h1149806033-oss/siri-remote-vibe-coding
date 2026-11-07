import Foundation

public enum BossRemoteHCIConstants {
    public static let machServiceName = "com.bossremote.hci"
    public static let expectedClientIdentifier = "com.bossremote.dev"
    public static let serviceVersion = 1
}

@objc public protocol BossRemoteHCIServiceProtocol {
    func prepareConfiguration(reply: @escaping (Bool, String) -> Void)
    func releaseConfiguration(reply: @escaping (Bool, String) -> Void)
}

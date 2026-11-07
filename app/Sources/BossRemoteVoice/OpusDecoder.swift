import Darwin
import Foundation

public final class OpusDecoder {
    private typealias Create = @convention(c) (
        Int32,
        Int32,
        UnsafeMutablePointer<Int32>?
    ) -> OpaquePointer?
    private typealias Destroy = @convention(c) (OpaquePointer?) -> Void
    private typealias Decode = @convention(c) (
        OpaquePointer?,
        UnsafePointer<UInt8>?,
        Int32,
        UnsafeMutablePointer<Int16>?,
        Int32,
        Int32
    ) -> Int32

    private let library: UnsafeMutableRawPointer
    private let decoder: OpaquePointer
    private let destroy: Destroy
    private let decode: Decode
    public let sampleRate: Int32

    public init?(sampleRate: Int32 = 16_000) {
        let candidates: [String] = [
            Bundle.main.privateFrameworksURL?
                .appendingPathComponent("libopus.0.dylib").path,
            Bundle.main.resourceURL?
                .appendingPathComponent("libopus.0.dylib").path,
            ProcessInfo.processInfo.environment["BOSS_REMOTE_OPUS_LIBRARY"],
            "/opt/homebrew/opt/opus/lib/libopus.0.dylib",
            "/usr/local/opt/opus/lib/libopus.0.dylib",
        ].compactMap { $0 }

        guard let path = candidates.first(where: {
            FileManager.default.isReadableFile(atPath: $0)
        }), let library = dlopen(path, RTLD_NOW | RTLD_LOCAL),
              let createSymbol = dlsym(library, "opus_decoder_create"),
              let destroySymbol = dlsym(library, "opus_decoder_destroy"),
              let decodeSymbol = dlsym(library, "opus_decode")
        else { return nil }

        let create = unsafeBitCast(createSymbol, to: Create.self)
        let destroy = unsafeBitCast(destroySymbol, to: Destroy.self)
        let decode = unsafeBitCast(decodeSymbol, to: Decode.self)
        var error: Int32 = -1
        guard let decoder = create(sampleRate, 1, &error), error == 0 else {
            dlclose(library)
            return nil
        }
        self.library = library
        self.decoder = decoder
        self.destroy = destroy
        self.decode = decode
        self.sampleRate = sampleRate
    }

    deinit {
        destroy(decoder)
        dlclose(library)
    }

    public func decode(_ packet: Data) -> [Int16]? {
        guard !packet.isEmpty else { return nil }
        var pcm = [Int16](repeating: 0, count: 1920)
        let count = packet.withUnsafeBytes { raw in
            pcm.withUnsafeMutableBufferPointer { output in
                decode(
                    decoder,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    Int32(packet.count),
                    output.baseAddress,
                    Int32(output.count),
                    0
                )
            }
        }
        guard count > 0 else { return nil }
        pcm.removeLast(pcm.count - Int(count))
        return pcm
    }
}

import Foundation

public struct ModelDescriptor: Codable, Equatable, Sendable {
    public let id: String
    public let revision: String
    public let fileName: String
    public let downloadURL: URL
    public let byteCount: Int64
    public let sha256: String
    public let license: String

    public init(
        id: String,
        revision: String,
        fileName: String,
        downloadURL: URL,
        byteCount: Int64,
        sha256: String,
        license: String
    ) {
        self.id = id
        self.revision = revision
        self.fileName = fileName
        self.downloadURL = downloadURL
        self.byteCount = byteCount
        self.sha256 = sha256
        self.license = license
    }

    public static let whisperLargeV3TurboQ5 = ModelDescriptor(
        id: "whisper-large-v3-turbo-q5_0",
        revision: "5359861c739e955e79d9a303bcbc70fb988958b1",
        fileName: "ggml-large-v3-turbo-q5_0.bin",
        downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo-q5_0.bin")!,
        byteCount: 574_041_195,
        sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2",
        license: "MIT"
    )
}

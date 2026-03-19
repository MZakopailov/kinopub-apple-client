import Foundation

struct DownloadTaskDescriptor<Meta: Codable & Equatable>: Codable {
  let url: URL
  let metadata: Meta
}

enum DownloadTaskDescriptionCoder {
  static func encode<Meta: Codable & Equatable>(url: URL, metadata: Meta) -> String? {
    let descriptor = DownloadTaskDescriptor(url: url, metadata: metadata)
    guard let data = try? JSONEncoder().encode(descriptor) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  static func decode<Meta: Codable & Equatable>(_ taskDescription: String?) -> DownloadTaskDescriptor<Meta>? {
    guard let taskDescription,
          let data = taskDescription.data(using: .utf8) else {
      return nil
    }

    return try? JSONDecoder().decode(DownloadTaskDescriptor<Meta>.self, from: data)
  }
}

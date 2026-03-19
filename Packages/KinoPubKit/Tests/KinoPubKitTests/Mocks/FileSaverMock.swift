//
//  FileSaverMock.swift
//
//
//  Created by Kirill Kunst on 22.07.2023.
//

import Foundation
@testable import KinoPubKit

class FileSaverMock: FileSaving {
  var shouldThrowError = false
  var didSaveFileCalled = false
  var savedFileSourceURL: URL?
  var savedFileDestinationURL: URL?
  var removedFileURLs: [URL] = []
  let documentsDirectoryURL: URL

  init(documentsDirectoryURL: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)) {
    self.documentsDirectoryURL = documentsDirectoryURL
    try? FileManager.default.createDirectory(at: documentsDirectoryURL, withIntermediateDirectories: true)
  }

  func saveFile(from sourceURL: URL, to destinationURL: URL) throws {
    didSaveFileCalled = true
    savedFileSourceURL = sourceURL
    savedFileDestinationURL = destinationURL

    if shouldThrowError {
      throw NSError(domain: "FileSaverMockErrorDomain", code: 123, userInfo: nil)
    }
  }

  func removeFile(at sourceURL: URL) throws {
    removedFileURLs.append(sourceURL)

    if shouldThrowError {
      throw NSError(domain: "FileSaverMockErrorDomain", code: 456, userInfo: nil)
    }
  }

  func getDocumentsDirectoryURL(forFilename filename: String) -> URL {
    documentsDirectoryURL.appendingPathComponent(filename)
  }
}

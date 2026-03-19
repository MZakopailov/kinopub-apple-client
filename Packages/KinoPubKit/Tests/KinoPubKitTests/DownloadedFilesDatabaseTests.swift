//
//  DownloadedFilesDatabaseTests.swift
//
//
//  Created by Kirill Kunst on 22.07.2023.
//

import Foundation
import XCTest
@testable import KinoPubKit

final class DownloadedFilesDatabaseTests: XCTestCase {
  typealias TestMeta = String

  var downloadedFilesDatabase: DownloadedFilesDatabase<TestMeta>!
  var fileSaverMock: FileSaverMock1!

  override func setUp() {
    super.setUp()

    fileSaverMock = FileSaverMock1()
    downloadedFilesDatabase = DownloadedFilesDatabase(fileSaver: fileSaverMock)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: fileSaverMock.documentsDirectoryURL)
    downloadedFilesDatabase = nil
    fileSaverMock = nil
    super.tearDown()
  }

  func testSaveFilePersistsFileInfo() {
    let fileInfo = DownloadedFileInfo(originalURL: URL(string: "http://example.com/testfile.txt")!,
                                      localFilename: "testfile.txt",
                                      downloadDate: Date(),
                                      metadata: "meta")

    downloadedFilesDatabase.save(fileInfo: fileInfo)

    XCTAssertEqual(downloadedFilesDatabase.readData(), [fileInfo])
  }

  func testReadDataReturnsNilForInvalidPropertyList() throws {
    try Data("invalid".utf8).write(to: fileSaverMock.dataFileURL)

    XCTAssertNil(downloadedFilesDatabase.readData())
  }

  func testReadDataReturnsNewestItemsFirst() {
    let older = DownloadedFileInfo(originalURL: URL(string: "http://example.com/old.txt")!,
                                   localFilename: "old.txt",
                                   downloadDate: Date(timeIntervalSince1970: 10),
                                   metadata: "old")
    let newer = DownloadedFileInfo(originalURL: URL(string: "http://example.com/new.txt")!,
                                   localFilename: "new.txt",
                                   downloadDate: Date(timeIntervalSince1970: 20),
                                   metadata: "new")

    downloadedFilesDatabase.writeData([older, newer])

    XCTAssertEqual(downloadedFilesDatabase.readData(), [newer, older])
  }

  func testRemoveDeletesEntryAndDelegatesFileRemoval() {
    let fileInfo = DownloadedFileInfo(originalURL: URL(string: "http://example.com/testfile.txt")!,
                                      localFilename: "testfile.txt",
                                      downloadDate: Date(),
                                      metadata: "meta")
    downloadedFilesDatabase.writeData([fileInfo])

    downloadedFilesDatabase.remove(fileInfo: fileInfo)

    XCTAssertEqual(downloadedFilesDatabase.readData(), [])
    XCTAssertEqual(fileSaverMock.removedFileURLs, [fileInfo.originalURL])
  }
}

final class FileSaverMock1: FileSaving {
  let documentsDirectoryURL: URL
  var removedFileURLs: [URL] = []
  var dataFileURL: URL {
    getDocumentsDirectoryURL(forFilename: "downloadedFiles.plist")
  }

  init(documentsDirectoryURL: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)) {
    self.documentsDirectoryURL = documentsDirectoryURL
    try? FileManager.default.createDirectory(at: documentsDirectoryURL, withIntermediateDirectories: true)
  }

  func saveFile(from sourceURL: URL, to destinationURL: URL) throws {}

  func removeFile(at sourceURL: URL) throws {
    removedFileURLs.append(sourceURL)
  }

  func getDocumentsDirectoryURL(forFilename filename: String) -> URL {
    documentsDirectoryURL.appendingPathComponent(filename)
  }
}

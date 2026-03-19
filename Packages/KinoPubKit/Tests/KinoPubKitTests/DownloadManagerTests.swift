//
//  DownloadManagerTests.swift
//
//
//  Created by Kirill Kunst on 22.07.2023.
//

import Foundation
import XCTest
@testable import KinoPubKit

final class DownloadManagerTests: XCTestCase {
  typealias TestMeta = String

  var downloadManager: DownloadManager<TestMeta>!
  var downloadedFilesDatabase: DownloadedFilesDatabase<TestMeta>!
  var fileSaverMock: FileSaverMock!

  override func setUp() {
    super.setUp()

    fileSaverMock = FileSaverMock()
    downloadedFilesDatabase = DownloadedFilesDatabase(fileSaver: fileSaverMock)
    downloadManager = DownloadManager(fileSaver: fileSaverMock, database: downloadedFilesDatabase)
  }

  override func tearDown() {
    downloadManager.session.invalidateAndCancel()
    try? FileManager.default.removeItem(at: fileSaverMock.documentsDirectoryURL)
    downloadManager = nil
    downloadedFilesDatabase = nil
    fileSaverMock = nil
    super.tearDown()
  }

  func testStartDownloadTracksActiveDownload() {
    let url = URL(string: "http://example.com/testfile.txt")!
    let download = downloadManager.startDownload(url: url, withMetadata: "meta")
    defer { download.task?.cancel() }

    let descriptor: DownloadTaskDescriptor<TestMeta>? = DownloadTaskDescriptionCoder.decode(download.task?.taskDescription)

    XCTAssertEqual(download.state, .inProgress)
    XCTAssertEqual(download.metadata, "meta")
    XCTAssertNotNil(downloadManager.activeDownloads[url])
    XCTAssertEqual(descriptor?.url, url)
    XCTAssertEqual(descriptor?.metadata, "meta")
  }

  func testCompleteDownloadRemovesActiveDownload() {
    let url = URL(string: "http://example.com/testfile.txt")!
    let download = downloadManager.startDownload(url: url, withMetadata: "meta")
    defer { download.task?.cancel() }

    downloadManager.completeDownload(url)

    XCTAssertNil(downloadManager.activeDownloads[url])
  }

  func testDidFinishDownloadingTo_Success() {
    let url = URL(string: "http://example.com/testfile.txt")!
    let locationURL = URL(fileURLWithPath: "/path/to/temporary/location.txt")
    let download = downloadManager.startDownload(url: url, withMetadata: "meta")

    download.task?.cancel()
    download.task = URLSessionDownloadTaskMock(url: url, state: .running)

    downloadManager.urlSession(downloadManager.session,
                               downloadTask: download.task!,
                               didFinishDownloadingTo: locationURL)

    XCTAssertTrue(fileSaverMock.didSaveFileCalled)
    XCTAssertEqual(fileSaverMock.savedFileSourceURL, locationURL)
    XCTAssertEqual(fileSaverMock.savedFileDestinationURL, fileSaverMock.getDocumentsDirectoryURL(forFilename: "testfile.txt"))
    XCTAssertEqual(downloadedFilesDatabase.readData()?.first?.metadata, "meta")
  }

  func testDidFinishDownloadingTo_UsesTaskDescriptionWhenDownloadWasRestored() {
    let url = URL(string: "http://example.com/restored.txt")!
    let locationURL = URL(fileURLWithPath: "/path/to/temporary/restored.txt")
    let task = URLSessionDownloadTaskMock(url: url, state: .running)
    task.taskDescription = DownloadTaskDescriptionCoder.encode(url: url, metadata: "restored")

    downloadManager.urlSession(downloadManager.session,
                               downloadTask: task,
                               didFinishDownloadingTo: locationURL)

    XCTAssertTrue(fileSaverMock.didSaveFileCalled)
    XCTAssertEqual(downloadedFilesDatabase.readData()?.first?.metadata, "restored")
  }

  func testDidWriteDataUpdatesProgress() {
    let url = URL(string: "http://example.com/testfile.txt")!
    let download = downloadManager.startDownload(url: url, withMetadata: "meta")
    let task = URLSessionDownloadTaskMock(url: url, state: .running)
    task.taskDescription = download.task?.taskDescription
    download.task?.cancel()
    download.task = task

    let expectation = expectation(description: "progress updated")

    downloadManager.urlSession(downloadManager.session,
                               downloadTask: task,
                               didWriteData: 1024,
                               totalBytesWritten: 1024,
                               totalBytesExpectedToWrite: 2048)

    DispatchQueue.main.async {
      XCTAssertEqual(download.progress, 0.5, accuracy: 0.001)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1.0)
  }

  func testBackgroundCompletionHandlerIsCalledWhenBackgroundEventsFinish() {
    let expectation = expectation(description: "background completion handler called")

    downloadManager.handleEvents(forBackgroundURLSession: downloadManager.session.configuration.identifier ?? "") {
      expectation.fulfill()
    }

    downloadManager.urlSessionDidFinishEvents(forBackgroundURLSession: downloadManager.session)

    wait(for: [expectation], timeout: 1.0)
  }
}

final class URLSessionDownloadTaskMock: URLSessionDownloadTask, @unchecked Sendable {
  private let url: URL?
  private let mockedState: URLSessionTask.State
  private var storedTaskDescription: String?

  init(url: URL? = nil, state: URLSessionTask.State = .suspended) {
    self.url = url
    self.mockedState = state
    super.init()
  }

  override var originalRequest: URLRequest? {
    guard let url else {
      return nil
    }

    return URLRequest(url: url)
  }

  override var state: URLSessionTask.State {
    mockedState
  }

  override var taskDescription: String? {
    get { storedTaskDescription }
    set { storedTaskDescription = newValue }
  }

  override func cancel() {}

  override func cancel(byProducingResumeData completionHandler: @escaping (Data?) -> Void) {
    completionHandler(nil)
  }
}

//
//  DownloadManager.swift
//
//
//  Created by Kirill Kunst on 22.07.2023.
//

import Foundation
import OSLog
import KinoPubLogging

private let downloadManagerBackgroundSessionIdentifier = "com.kinopub.backgroundDownloadSession"

public protocol DownloadManaging {
  associatedtype Meta: Codable & Equatable
  
  var session: URLSession { get }
  func startDownload(url: URL, withMetadata metadata: Meta) -> Download<Meta>
  func removeDownload(for url: URL)
  func completeDownload(_ url: URL)
}

public class DownloadManager<Meta: Codable & Equatable>: NSObject, URLSessionDownloadDelegate, DownloadManaging {
  @Published public var activeDownloads: [URL: Download<Meta>] = [:]
  private var fileSaver: FileSaving
  private var database: DownloadedFilesDatabase<Meta>
  private var backgroundSessionCompletionHandler: (() -> Void)?

  public init(fileSaver: FileSaving, database: DownloadedFilesDatabase<Meta>) {
    self.fileSaver = fileSaver
    self.database = database
    super.init()
    restoreActiveDownloads()
  }

  lazy public var session: URLSession = {
    let config = URLSessionConfiguration.background(withIdentifier: downloadManagerBackgroundSessionIdentifier)
    return URLSession(configuration: config, delegate: self, delegateQueue: nil)
  }()

  public func startDownload(url: URL, withMetadata metadata: Meta) -> Download<Meta> {
    let download = Download(url: url, metadata: metadata, manager: self)
    download.resume()
    activeDownloads[url] = download
    return download
  }
  
  public func removeDownload(for url: URL) {
    guard let download = activeDownloads[url] else {
      return
    }
    
    download.pause()
    activeDownloads[url] = nil
  }

  public func completeDownload(_ url: URL) {
    updateActiveDownloadsOnMain { downloads in
      downloads[url] = nil
    }
  }

  public func handleEvents(forBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
    guard identifier == downloadManagerBackgroundSessionIdentifier else {
      completionHandler()
      return
    }

    backgroundSessionCompletionHandler = completionHandler
    restoreActiveDownloads()
  }

  // MARK: URLSessionDownloadDelegate methods

  public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    guard let context = downloadContext(for: downloadTask) else { return }
    let sourceURL = context.url
    Logger.kit.debug("[DOWNLOAD] Download finished: \(location)")

    let destinationURL = fileSaver.getDocumentsDirectoryURL(forFilename: sourceURL.lastPathComponent)

    do {
      try fileSaver.saveFile(from: location, to: destinationURL)
      Logger.kit.info("[DOWNLOAD] File: \(location) moved to documents folder")

      let fileInfo = DownloadedFileInfo(originalURL: sourceURL, localFilename: sourceURL.lastPathComponent, downloadDate: Date(), metadata: context.metadata)
      database.save(fileInfo: fileInfo)
    } catch {
      Logger.kit.error("[DOWNLOAD] Error during moving file: \(error)")
    }

    completeDownload(sourceURL)
  }

  public func urlSession(_ session: URLSession,
                         downloadTask: URLSessionDownloadTask,
                         didWriteData bytesWritten: Int64,
                         totalBytesWritten: Int64,
                         totalBytesExpectedToWrite: Int64) {
    guard totalBytesExpectedToWrite > 0,
          let url = downloadURL(for: downloadTask),
          let download = activeDownloads[url] else {
      return
    }

      let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
      Logger.kit.debug("[DOWNLOAD] progress for download: \(download.url), value: \(progress)")
      DispatchQueue.main.async {
        download.updateProgress(progress)
      }
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error = error, let url = task.originalRequest?.url {
      Logger.kit.debug("[DOWNLOAD] Download error for \(url): \(error)")
      completeDownload(url)
    }
  }

  public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    guard session.configuration.identifier == downloadManagerBackgroundSessionIdentifier else {
      return
    }

    DispatchQueue.main.async { [weak self] in
      self?.backgroundSessionCompletionHandler?()
      self?.backgroundSessionCompletionHandler = nil
    }
  }

  private func restoreActiveDownloads() {
    session.getAllTasks { [weak self] tasks in
      guard let self else { return }

      let restoredDownloads = tasks.reduce(into: [URL: Download<Meta>]()) { partialResult, task in
        guard let downloadTask = task as? URLSessionDownloadTask,
              let descriptor: DownloadTaskDescriptor<Meta> = DownloadTaskDescriptionCoder.decode(downloadTask.taskDescription),
              task.state != .canceling,
              task.state != .completed else {
          return
        }

        partialResult[descriptor.url] = Download(restoringTask: downloadTask,
                                                 url: descriptor.url,
                                                 metadata: descriptor.metadata,
                                                 manager: self)
      }

      self.updateActiveDownloadsOnMain { downloads in
        downloads.merge(restoredDownloads) { current, _ in current }
      }
    }
  }

  private func downloadURL(for task: URLSessionTask) -> URL? {
    if let url = task.originalRequest?.url {
      return url
    }

    let descriptor: DownloadTaskDescriptor<Meta>? = DownloadTaskDescriptionCoder.decode(task.taskDescription)
    return descriptor?.url
  }

  private func downloadContext(for task: URLSessionTask) -> DownloadTaskDescriptor<Meta>? {
    if let url = task.originalRequest?.url,
       let download = activeDownloads[url] {
      return DownloadTaskDescriptor(url: url, metadata: download.metadata)
    }

    let descriptor: DownloadTaskDescriptor<Meta>? = DownloadTaskDescriptionCoder.decode(task.taskDescription)
    return descriptor
  }

  private func updateActiveDownloadsOnMain(_ update: @escaping (inout [URL: Download<Meta>]) -> Void) {
    let performUpdate = {
      update(&self.activeDownloads)
    }

    if Thread.isMainThread {
      performUpdate()
    } else {
      DispatchQueue.main.async(execute: performUpdate)
    }
  }
}

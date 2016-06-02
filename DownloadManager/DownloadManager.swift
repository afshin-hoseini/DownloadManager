//
//  DownloadManager.swift
//  DownloadManager
//
//  Created by Afshin Hoseini on 5/11/16.
//  Copyright © 2016 Afshin Hoseini. All rights reserved.
//

import Foundation


public enum DownloadStatus {
    
    case NotStarted
    case Started
    
    case GettingInformation
    case GotFileInformation
    
    case Downloading
    
    case Successful
    case CouldntMakeFile
    case Cancelled
    case ErrorOccurred(response: NSHTTPURLResponse?, error: NSError?)
}


typealias OnPartStarted = (part: Part) -> Void
typealias OnPartGotTheServerResponse = (part: Part, response: NSHTTPURLResponse) -> Void
typealias OnPartProgress = (part: Part, totalReadBytes: Int64, partFileSize: Int64) -> Void
typealias OnPartFinished = (part: Part, success: Bool, status: ConnectionStatus) -> Void

public typealias MyFunction = () -> Void


func sync(locker: NSLock, block: ()->Void) {
    
    
    locker.lock()
    
    defer {
        
        locker.unlock()
    }
    
    block()
    
}


public class DownloadManager {
    
    
    
    
    let tag: AnyObject?
    let connectionCount: Int
    let retryCount: Int
    let url: String
    let destinationPath: String
    
    private let partSize: Int64 = (1024*1024) * 2 //2 MegaBytes
    private let partDispatcherLock = NSLock()
    
    private var isPartialContent = false
    private var fileSize: Int64 = 0
    private var totalReadBytes: Int64 = 0
    
    private var parts: [Part]!
    private var retryTimes = 0
    private var currentDownloadingPartCount = 0
    private var numberOfSuccessfullyDownloadedParts = 0
    private var cancelRequested = false
    
    private var tempPartFilesPath = ""
    
    private var downloadQueue: NSOperationQueue!
    private var partStartQueue: NSOperationQueue!
    private var partGotResponseQueue: NSOperationQueue!
    private var partProgressQueue: NSOperationQueue!
    private var partFinishQueue: NSOperationQueue!
    
    
    public var onDownloadManagerStarted: ((downloadManager: DownloadManager, downloadStatus: DownloadStatus) -> Void)?
    public var onDownloadManagerGotFileHeader: ((downloadManager: DownloadManager, fileHeader: NSHTTPURLResponse) -> Void)?
    public var onDownloadManagerProgress: ((downloadManager: DownloadManager, totalReadBytes: Int64, fileSize: Int64) -> Void)?
    public var onDownlodManagerFinished: ((downloadManager: DownloadManager, sucess: Bool, status: DownloadStatus ) -> Void)?
    
    private var _downlaodStatus = DownloadStatus.NotStarted
    private var _startNotified = false
    private var _finishNotified = false
    
    
    private var mustCancelJob: Bool {
        
        return (self.retryTimes > self.retryCount) || cancelRequested
    }
    
    
    private var downloadStatus: DownloadStatus {
        
        return _downlaodStatus
    }
    
    
    //MARK: - Initializers
    
    public init?(url: String, _ destinationPath: String, _ tag: AnyObject?, _ connectionCount: Int, _ retryCount: Int) {
        
        self.url = url
        self.destinationPath = destinationPath
        self.tag = tag
        self.connectionCount = connectionCount
        self.retryCount = retryCount
        
        if let tmpDir = makePathForTemporaryPartFiles() {
            
            tempPartFilesPath = tmpDir
            createQueues()
        }
        else {
            
            print("Couldn't create part files temporary folder.")
            return nil
        }
        
    }
    
    
    private func makePathForTemporaryPartFiles() -> String? {
        
        var tempPartFilesPath: String? = NSTemporaryDirectory()
        
        if tempPartFilesPath!.characters.last != "/" {
            
            tempPartFilesPath = tempPartFilesPath! + "/"
        }
        tempPartFilesPath = tempPartFilesPath! + "DlMan_\(NSDate().timeIntervalSince1970)"
        
        do {
            
            try NSFileManager.defaultManager().createDirectoryAtPath(tempPartFilesPath!, withIntermediateDirectories: true, attributes: nil)
        } catch {
            
            tempPartFilesPath = nil
        }
        
        return tempPartFilesPath
    }
    
    
    private func createQueues() {
        
        downloadQueue = NSOperationQueue()
        downloadQueue.qualityOfService = .UserInitiated
        downloadQueue.maxConcurrentOperationCount = connectionCount
        downloadQueue.name = "Download manager queue"
        
        partStartQueue = NSOperationQueue()
        partStartQueue.qualityOfService = .UserInitiated
        partStartQueue.maxConcurrentOperationCount = 1
        partStartQueue.name = "On parts start queue"
        
        partGotResponseQueue = NSOperationQueue()
        partGotResponseQueue.qualityOfService = .UserInitiated
        partGotResponseQueue.maxConcurrentOperationCount = 1
        partGotResponseQueue.name = "On parts got response queue"
        
        partProgressQueue = NSOperationQueue()
        partProgressQueue.qualityOfService = .UserInitiated
        partProgressQueue.maxConcurrentOperationCount = 1
        partProgressQueue.name = "On parts progress queue"
        
        partFinishQueue = NSOperationQueue()
        partFinishQueue.qualityOfService = .UserInitiated
        partFinishQueue.maxConcurrentOperationCount = 1
        partFinishQueue.name = "On parts finished queue"
    }

    
    
    
    //MARK: - Methods
    
    
    
    public func start() {

        self.getFileInfo()
 
    }
    
    
    public func cancel(isCancelledByUser: Bool = true) {
        
        if isCancelledByUser {
        
            notifyFinished(DownloadStatus.Cancelled)
        }
        
        cancelRequested = true
        
        if parts != nil {
            
            for part in parts {
                
                part.cancel()
            }
        }
        
        removePartTempFolder()
    }
    
    
    func getFileInfo() {
        
        notifyStarted(DownloadStatus.Started)
        notifyStarted(DownloadStatus.GettingInformation)

        let testPart = Part(fileAddress: url, "", range: (from: 0, to: 10000000), partName: "TestPart", isThisAtestPart: true)
        
        testPart.onGotServerResponse = { (part: Part, response: NSHTTPURLResponse) -> Void in
            
            let status = ConnectionStatus(serverResponse: response, withErr: nil)
            
            if status == ConnectionStatus.Success {
                
                self.isPartialContent = (response.statusCode == 206)
                self.fileSize = part.wholeFileSize
                
                self.notifyGotFileInformation(response)
            }
        }
        
        testPart.onPartFinished = { (part: Part, success: Bool, status: ConnectionStatus) -> Void in
            
            if status == ConnectionStatus.Success {
                
                self.parts = self.provideParts()
                self.dispatchPartsToDownload()
                
                self.notifyStarted(DownloadStatus.Downloading)
                
            }
            else {
                
                self.notifyFinished(DownloadStatus.ErrorOccurred(response: part.response, error: part.error))
                print("Can not get file info")
            }
        }
        
        downloadQueue.addOperation(testPart)

    }
    
    
    func provideParts() -> [Part] {
        
        var parts = [Part]()
        
        if !isPartialContent || fileSize <= 0 {
            
            let part = Part(fileAddress: url, tempPartFilesPath, range: nil, partName: "TheOnlyPart")
            setPartCallbacks(part)
            parts.append(part)
        }
        else {
            
            var partSize: Int64 = self.partSize
            var partCount = 0
            
            if self.partSize < 512 {
                
                partSize = (fileSize / Int64(connectionCount))
            }
            
            partCount = Int(fileSize / partSize)
            
            if fileSize % partSize > 0 {
                
                partCount = partCount + 1
            }
            
            
            for idx in 0..<partCount {
                
                let from = (Int64(idx) * partSize)
                let to = (Int64(idx+1) * partSize) - 1
                
                let part = Part(fileAddress: url, tempPartFilesPath, range: (from: from, to: to), partName: "part\(idx)")
                setPartCallbacks(part)
                
                parts.append(part)
            }
            
            
        }
        
        
        
        return parts
    }
    
    
    func setPartCallbacks(part: Part) {
        
        part.onPartStarted = onPartStarted
        part.onGotServerResponse = onPartGotTheServerResponse
        part.onPartProgress = onPartProgress
        part.onPartFinished = onPartFinished
    }
    
    
    func dispatchPartsToDownload() {
        
        sync(partDispatcherLock) {
            
            while (self.currentDownloadingPartCount < self.connectionCount) {
                
                let nextPart = self.getNextNotDownloadedPartPart()
                
                if let nextPart = nextPart {
                    
                    nextPart.status = Part.Status.InProgress
                    self.currentDownloadingPartCount = self.currentDownloadingPartCount + 1
                    self.downloadQueue.addOperation(nextPart)
                }
                else {
                    
                    break
                }
            }
            
        }
    }

    
    func getNextNotDownloadedPartPart() -> Part? {
    
        guard !mustCancelJob else { return nil }
        
        var nextPart: Part? = nil

        
        for part in parts {
            
            var thisPartMustBeDownloaded = false
            
            switch part.status {
                
                case .InProgress : thisPartMustBeDownloaded = false
                case .Completed : thisPartMustBeDownloaded = false
                default: thisPartMustBeDownloaded = true
            }
            
            if thisPartMustBeDownloaded {
                
                nextPart = part
                break
            }
        }
        
        return nextPart
    }
    
    
    
    func concatParts() {
        
        do{
           
            let destinationPath = self.destinationPath
            
            let f = NSURL(fileURLWithPath: destinationPath)
            
            try NSFileManager.defaultManager().createDirectoryAtURL(f.URLByDeletingLastPathComponent!, withIntermediateDirectories: true, attributes: nil)
            
            var shouldOpenAppendable = false
            
            for part in parts {
                
                let outputStream = NSOutputStream(toFileAtPath: destinationPath, append: shouldOpenAppendable)
                
                outputStream?.open()
                
                if !part.writeDataOnOutPutStream(outputStream!) {
                    
                    print("Error occured while writing \(part.partName)")
                }
                part.removeFile()
                
                outputStream?.close()
                shouldOpenAppendable = true
            }
            
            notifyFinished(DownloadStatus.Successful)
            
        } catch {
            
            notifyFinished(DownloadStatus.CouldntMakeFile)
        }
        
        removePartTempFolder()
    }
    
    
    private func removePartTempFolder() {
        
        _ = try? NSFileManager.defaultManager().removeItemAtPath(tempPartFilesPath)
    }
    
    
    func getItemIndexFromArray(item: NSObject, array: [NSObject]) -> Int {
        
        var idx: Int = -1
        
        
        for i in 0..<array.count {
            
            if array[i] == item {
                
                idx = i
                break
            }
        }
        
        return idx
        
    }
    
    
    //MARK: - Notifiers
    
    func notifyStarted(downloadStatus: DownloadStatus) {
        
        _downlaodStatus = downloadStatus
        onDownloadManagerStarted?(downloadManager: self, downloadStatus: downloadStatus)
    }
    
    
    func notifyGotFileInformation(fileHeader: NSHTTPURLResponse) {
        
        _downlaodStatus = .GotFileInformation
        onDownloadManagerGotFileHeader?(downloadManager: self, fileHeader: fileHeader)
    }
    
    
    func notifyProgress() {
        
        _downlaodStatus = DownloadStatus.Downloading
        onDownloadManagerProgress?(downloadManager: self, totalReadBytes: totalReadBytes, fileSize: fileSize)
    }
    
    
    func notifyFinished(status: DownloadStatus) {
        
        guard !_finishNotified else { return }
        
        var success = false
        
        _finishNotified = true
        _downlaodStatus = status
        
        switch downloadStatus {
            
            case .Successful:
                success = true
            default:
                success = false
        }
        
        onDownlodManagerFinished?(downloadManager: self, sucess: success, status: downloadStatus)
    }
    
    
    //MARK: - Part callbacks
    
    
    func onPartStarted( part: Part) {
        
        partStartQueue.addOperation(NSBlockOperation {
            
//            print("\(part.partName) is started")
            
        })
    }
    
    
    func onPartGotTheServerResponse(part: Part, response: NSHTTPURLResponse) {
        
        partGotResponseQueue.addOperation(NSBlockOperation {
            
//            print("\(part.partName) will download \(part.range!.from) to \(part.range!.to) - size = \(part.rangeSize)")
            
            
        })
    }
    
    
    func onPartProgress(part: Part, totalReadBytes: Int64, partFileSize: Int64) {
        
        partProgressQueue.addOperation(NSBlockOperation {
            
            self.totalReadBytes += totalReadBytes
            self.notifyProgress()
            
            
        })

    }
    
    
    func onPartFinished(part: Part, success: Bool, status: ConnectionStatus) {
        
        partFinishQueue.addOperation(NSBlockOperation {
            
            self.currentDownloadingPartCount = self.currentDownloadingPartCount - 1
            
//            print("\(part.partName) finished \(success ? "successfully" : "unsuccessfully") - Downloaded: \(part.downloadedSize)")
            
            if success {
                
                self.numberOfSuccessfullyDownloadedParts = self.numberOfSuccessfullyDownloadedParts + 1
                
                if self.numberOfSuccessfullyDownloadedParts == self.parts.count && !self.mustCancelJob {
                    
                    self.concatParts()
                }
                else {
                
                    self.dispatchPartsToDownload()
                }
                
            }
            else if status == ConnectionStatus.NoInternetConnection {
                
                self.notifyFinished(DownloadStatus.ErrorOccurred(response: part.response, error: part.error))
            }
            else {
                
                self.retryTimes = self.retryTimes + 1
                
//                print("retryTimes: \(self.retryTimes)")
                
                if self.retryTimes <= self.retryCount {
                    
                    part.removeFile()
                    
                    let reNewedPart = Part(fileAddress: self.url, self.tempPartFilesPath, range: part.range, partName: part.partName)
                    self.setPartCallbacks(reNewedPart)
                    
                    self.parts[self.getItemIndexFromArray(part, array: self.parts)] = reNewedPart
                    
                    self.dispatchPartsToDownload()
                }
                else {
                    
                    self.parts.removeAtIndex(self.getItemIndexFromArray(part, array: self.parts))
                    self.cancel(false)
                    
                    self.notifyFinished(DownloadStatus.ErrorOccurred(response: part.response, error: part.error))
                    
                    
                }
            }
            
        })
    }
   
    
}









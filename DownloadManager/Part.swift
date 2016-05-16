//
//  DownloadPart.swift
//  DownloadManager
//
//  Created by Afshin Hoseini on 5/11/16.
//  Copyright © 2016 Afshin Hoseini. All rights reserved.
//

import Foundation

typealias DownloadRange = (from: Int64, to: Int64)

class Part : NSOperation, NSURLConnectionDataDelegate  {
    
    //MARK: - Enums
    
    enum Status {
        
        case ErrorOccured(status: ConnectionStatus)
        case InProgress
        case Completed
        case WaitingToBeStarted
    }
    
    
    
    //MARK: - Stored properties
    
    private var fileAddress = ""
    private var destinationPath = ""
    private var _range: DownloadRange? = nil
    private var _partName = ""
    private var method = "GET"
    private var isThisAtestPart = false
    private var urlConnection: NSURLConnection? = nil
    private var _wholeFileSize: Int64 = 0
    private var _rangeSize: Int64 = 0
    private var outputStream: NSOutputStream? = nil
    private var buffer = NSMutableData()
    private var cancelRequested = false
    
    ///3 kilo bytes
    private let bufferFlushThreshold = 1024 * 3
    
    private var buffFlushTotal = 0
    
    var status: Status = Status.WaitingToBeStarted
    var downloadedSize: Int64 = 0;
    var isCompeleted = false
    
    var onPartStarted: OnPartStarted?
    var onGotServerResponse: OnPartGotTheServerResponse?
    var onPartProgress: OnPartProgress?
    var onPartFinished: OnPartFinished?
    
    
    var request: NSMutableURLRequest!
    
    var response: NSHTTPURLResponse? = nil
    var error: NSError? = nil
    
    
    //MARK: - Computed properties
    
    var partFile: String? {
        
        if destinationPath == "" {
            
            return nil
        }
        
        if destinationPath.characters.last != "/" {
            
            destinationPath = destinationPath + "/"
        }
        
        return destinationPath + partName
    }
    
    ///The file size that this part must download.
    var rangeSize: Int64 {
        
        return _rangeSize
    }
    
    
    var wholeFileSize: Int64 {
        
        return _wholeFileSize
    }
    
    
    var isRangedPart: Bool {
        
        return range != nil && range!.from >= 0 && range!.to > range!.from
    }
    
    
    var partName: String {
        
        return _partName
    }
    
    
    var range: DownloadRange? {
        
        return _range
    }
    
    
    //MARK: - Initializers
    
    init(fileAddress: String, _ destinationPath: String, range: (from: Int64, to: Int64)?, partName: String?, isThisAtestPart: Bool = false) {
        
        self.fileAddress = fileAddress
        
        self.destinationPath = destinationPath
        self._range = range
        self._partName = partName ?? "Part \(NSDate().timeIntervalSince1970)_\(rand())"
        self.method = isThisAtestPart ? "HEAD" : "GET"
        self.isThisAtestPart = isThisAtestPart
        
    }
    
    
    //MARK: - Methods
    
    override func cancel() {
        
        cancelRequested = true
        urlConnection?.cancel()
        outputStream?.close()
        removeFile()
        super.cancel()
    }
    
    override func main() {
        
        startDownload()
    }
    
    
    func removeFile() -> Bool {
        
        return (try? NSFileManager.defaultManager().removeItemAtPath(partFile!)) != nil ? true : false
    }
    
    
    func writeDataOnOutPutStream(outputStream: NSOutputStream) -> Bool {
        
        guard partFile != nil else { return false }
        
        var inputBuffer = [UInt8](count: 1024, repeatedValue: 0)
        var readCount = 1
        
        let partFile_inputStream = NSInputStream(fileAtPath: partFile!)
        
        guard partFile_inputStream != nil else { return false }
        
        partFile_inputStream!.open()
        
        var totalWroteBytes = 0
        
        while(readCount > 0) {
            
            readCount = partFile_inputStream!.read(&inputBuffer, maxLength: inputBuffer.count)
            
            
            
            if outputStream.write(inputBuffer, maxLength: readCount) < 0 {
            
                break
            }
            
        }
        
        partFile_inputStream!.close()
        
//        print("\(partName) wrote \(totalWroteBytes) bytes ")
        
        return readCount == 0
        
    }
    
    
    func startDownload() {
        
        guard !cancelRequested else { return }
        
        self.status = Status.InProgress
        
        request = NSMutableURLRequest(URL: NSURL(string: fileAddress)!, cachePolicy: .ReloadIgnoringLocalCacheData, timeoutInterval: 30)
        
        if isRangedPart {
            
            request.addValue("bytes=\(range!.from)-\(range!.to)", forHTTPHeaderField: "Range")
            request.HTTPMethod = method
        }
       
        urlConnection = NSURLConnection(request: request, delegate: self, startImmediately: false)
        urlConnection?.setDelegateQueue(NSOperationQueue.currentQueue())
//        print(NSOperationQueue.currentQueue())
        self.urlConnection!.start()
        
        self.onPartStarted?(part: self)
       
    }
    
    
    func openFileOutputStream() {
        
        guard let partFile = partFile else { return }
        
        self.outputStream = NSOutputStream(toFileAtPath: partFile, append: false)
        self.outputStream?.open()
        
    }
    
    
    func retreiveFileSizeFromResponse(response: NSHTTPURLResponse) -> (wholeFileSize:Int64, rangeSize: Int64) {
        
        
        var fileSize: Int64 = 0
        var rangeSize: Int64 = 0
        
        var str_rangeLenght = self.response!.allHeaderFields["Content-Range"]
        
        if str_rangeLenght != nil {
            
            let slashIdx = str_rangeLenght?.rangeOfString("/", options: NSStringCompareOptions.BackwardsSearch).location
            str_rangeLenght = str_rangeLenght?.substringFromIndex(slashIdx! + 1)
            fileSize = Int64((str_rangeLenght as? String) ?? "0")!
        }
        else {
            
            fileSize = 0
        }
        
        
        let contentLenghtProperty = self.response!.allHeaderFields["Content-Length"]
        
        if contentLenghtProperty != nil {
            
            if contentLenghtProperty is Int {
                
                rangeSize = contentLenghtProperty as! Int64
            }
            else if contentLenghtProperty is String {
                
                rangeSize = Int64(contentLenghtProperty as! String)!
            }
            else {
                
                rangeSize = 0
            }
            
        }
        else {
        
            rangeSize = 0
        }
        
        if rangeSize > fileSize {
            
            fileSize = rangeSize
        }
        
        return (fileSize, rangeSize)
    }
    
    
    func flushBuffer() {
        
        if outputStream != nil {
            
            let bytes = buffer.bytes
            let dataBytes = UnsafePointer<UInt8>(bytes)
            
            outputStream!.write(dataBytes, maxLength: buffer.length)
            buffer = NSMutableData()
        }
    }
    
    
    //MARK: - Delegate methods
    
    func connection(connection: NSURLConnection, didReceiveData data: NSData) {
        
        if outputStream != nil {
            
            buffer.appendData(data)
            
            if buffer.length > bufferFlushThreshold {
                
                flushBuffer()
            }
        }
        
        downloadedSize = downloadedSize + data.length
        
        
        onPartProgress?(part: self, totalReadBytes: Int64(data.length), partFileSize: rangeSize)
        
    }
    
    
    @objc func connection(connection: NSURLConnection, didFailWithError error: NSError) {
        
        self.error = error
        let status = ConnectionStatus(serverResponse: response, withErr: error)
        
        self.status = Status.ErrorOccured(status: status)
        outputStream?.close()
        self.onPartFinished?(part: self, success: false, status: status)
    }
    
    
    @objc func connection(connection: NSURLConnection, didReceiveResponse response: NSURLResponse) {
        
        self.response = response as? NSHTTPURLResponse
        
        let status = ConnectionStatus(serverResponse: response as? NSHTTPURLResponse, withErr: nil)
        
        if status == ConnectionStatus.Success {
            
            let size = retreiveFileSizeFromResponse(response as! NSHTTPURLResponse)
            self._wholeFileSize = size.wholeFileSize
            self._rangeSize = size.rangeSize
            openFileOutputStream()
        }
        else {
            
            self._wholeFileSize = -1
        }
        
        self.onGotServerResponse?(part: self, response: response as! NSHTTPURLResponse)
        
    }
    
    
    func connectionDidFinishLoading(connection: NSURLConnection) {
        
        flushBuffer()
        outputStream?.close()

        let status = ConnectionStatus(serverResponse: response, withErr: nil)
        
        if status == ConnectionStatus.Success {
            
            self.status = Status.Completed
        }
        else {
            
            self.status = Status.ErrorOccured(status: status)
        }
        
        self.onPartFinished?(part: self, success: status == ConnectionStatus.Success, status: status)
    }
    
    
    

    
}


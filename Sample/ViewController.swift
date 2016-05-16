//
//  ViewController.swift
//  Sample
//
//  Created by Afshin Hoseini on 5/11/16.
//  Copyright © 2016 Afshin Hoseini. All rights reserved.
//

import UIKit
import DownloadManager

class ViewController: UIViewController {
    
    var urlConnection: NSURLConnection? = nil
    var downloadMan: DownloadManager? = nil
    var isDownloadStarted = false
    var lastDownloadStartTime = NSTimeInterval(0)
    var isProgressNotified = true
    
    
    @IBOutlet weak var btnStartOrCancel: UIButton!
    @IBOutlet weak var editUrl: UITextField!
    @IBOutlet weak var connectionCountSteper: UIStepper!
    @IBOutlet weak var txtConnectionCount: UILabel!
    @IBOutlet weak var progressBar: UIProgressView!
    @IBOutlet weak var textView_information: UITextView!
    
    
    //MARK: - Life cycle methods

    override func viewDidLoad() {
        
        super.viewDidLoad()
        
    }
    
    
    //MARK: - Methods
    
    ///Starts the download process
    private func startDownload() {
        
        guard !isDownloadStarted else { return }
        
        textView_information.text = ""
        progressBar.progress = 0
        
        //Initializes the downloadmanager
        let connectionCount = Int(connectionCountSteper.value)
        let fileUrl = editUrl.text
        
        if fileUrl != nil && fileUrl != "" {
        
            //Determining destination path including filename
            let destinationFileName = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)[0] + "/Downloads/myFile.file"
            downloadMan = DownloadManager(url: fileUrl!, destinationFileName, nil, connectionCount, 1 + Int(connectionCount/2))
            
            //Sets the callback functions
            downloadMan?.onDownloadManagerStarted = onDownloadManagerStarted
            downloadMan?.onDownloadManagerGotFileHeader = onDownloadManagerGotFileHeader
            downloadMan?.onDownloadManagerProgress = onDownloadManagerProgress
            downloadMan?.onDownlodManagerFinished = onDownlodManagerFinished
            
            //Starts the download manager
            downloadMan!.start()
            lastDownloadStartTime = NSDate().timeIntervalSince1970
            
            isDownloadStarted = true
            btnStartOrCancel.setTitle("Cancel", forState: UIControlState.Normal)
            
        }
    }
    
    
    private func stopDownload() {
        
        guard isDownloadStarted else { return }
        
        downloadMan?.cancel()
        btnStartOrCancel.setTitle("Start", forState: UIControlState.Normal)
        isDownloadStarted = false
    }
    
    
    private func runOnMainThread(block: ()->Void) {
        
        dispatch_async(dispatch_get_main_queue()) {
            
            block()
        }
    }
    
    
    //MARK: - Downloader callbacks
    
    private func onDownloadManagerStarted(downloadManager: DownloadManager, downloadStatus: DownloadStatus) {
    
        runOnMainThread { 
            
            self.textView_information.text = self.textView_information.text + "Started \(downloadStatus) \n"
            self.isProgressNotified = false
        }
        
    }
    
    private func onDownloadManagerGotFileHeader(downloadManager: DownloadManager, fileHeader: NSHTTPURLResponse) {
        
        runOnMainThread { 
            
            self.textView_information.text = self.textView_information.text + "Got file information\n"
        }
        
    }
    
    private func onDownloadManagerProgress(downloadManager: DownloadManager, totalReadBytes: Int64, fileSize: Int64) {
    
        
        runOnMainThread { 
            
            if !self.isProgressNotified {
                
                self.isProgressNotified = true
                self.textView_information.text = self.textView_information.text + "Download is in progress. For more info check out the progress bar above.\n"
            }
            
            self.progressBar.progress = Float(totalReadBytes)/Float(fileSize)
        }
        
    }

    private func onDownlodManagerFinished(downloadManager: DownloadManager, sucess: Bool, status: DownloadStatus) {
    
        runOnMainThread { 
            
            self.textView_information.text = self.textView_information.text + "Finished \(sucess ? "successfully":"unsuccessfully").\n"
            self.textView_information.text = self.textView_information.text + "Here is download status: \(status)\n"
            
            self.textView_information.text = self.textView_information.text + "\n Duration:\n"
            
            let finishTime = NSDate().timeIntervalSince1970
            self.textView_information.text = self.textView_information.text + "\(finishTime - self.lastDownloadStartTime)"
            
            self.btnStartOrCancel.setTitle("Start", forState: UIControlState.Normal)
            self.isDownloadStarted = false
        }
        
        
        
    }

    
    
    //MARK: - Action events

    
    
    @IBAction func onBtnStartOrCancelClicked(sender: UIButton) {
        
        if isDownloadStarted {
            
            stopDownload()
        }
        else {
            
            startDownload()
        }
    }
    
    @IBAction func steperChanged(sender: AnyObject) {
        
        txtConnectionCount.text = String(Int((sender as! UIStepper).value))
    }
    

    

}


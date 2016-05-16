# DownloadManager
A simple, light and flexible multi thread or multi get download manager library for swift projects. As like as many other download managers, this library also uses multithreaded downloading approach, to download files faster. 

As you know it first examine the server to check if the server supports partial contents and then it simply provide parts. the it dispatchs parts to download according to determined concurrent connection quantity.

For more information about how to use the download manager please check [startDownload method in sample viewController](https://github.com/afshin-hoseini/DownloadManager/blob/master/Sample/ViewController.swift#L41)

## Supports:
1. Concurrent connections for faster downloads
2. Retry count
3. Full callback functions. Including start, progress and finish callbacks and more.

## Doesn't support yet:
1. Rsuming file download.

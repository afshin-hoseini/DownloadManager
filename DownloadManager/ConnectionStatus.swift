//
//  ConnectionStatus.swift
//  NativeApp
//
//  Created by Afshin Hoseini on 12/22/15.
//  Copyright © 2015 Bliksund AS. All rights reserved.
//

import Foundation

enum ConnectionStatus: Int {
    
    
    case Success = 200
    case UserIsNotAuthenticated = 401
    case NoInternetConnection = -1009
    case Unsuccess = 500
    case TimeOut = 504
    case Cancelled = -999
    case UpgradeRequired = 426
    
    var description: String {
        
        switch self {
            
        case .Success: return "connection was successful"
        case .UserIsNotAuthenticated: return "This User is not available"
        case .NoInternetConnection: return "There is no Internet connection"
        case .Unsuccess: return "connection was unsuccessful"
        case .TimeOut: return "The connection is timed out"
        case .Cancelled: return "Connection cancelled"
        case .UpgradeRequired: return "Upgrade required"
        }
        
    }
    
    
    
    init(serverResponse: NSHTTPURLResponse?, withErr: NSError?) {
        
        
        if let err = withErr where err.code >= -1009 && err.code <= -1004 {
            
            self = ConnectionStatus.NoInternetConnection
            
        }
        else if let err = withErr where err.code == ConnectionStatus.Cancelled.rawValue {
            
            self = ConnectionStatus.Cancelled
        }
        else {
            
            let statusCode: Int = (serverResponse == nil ? -1 : serverResponse!.statusCode)
            
            switch statusCode {
                
            case 200..<300 : self = ConnectionStatus.Success
            case 300..<400 : self = ConnectionStatus.Unsuccess
            case 401 : self = ConnectionStatus.UserIsNotAuthenticated
            case 426 : self = ConnectionStatus.UpgradeRequired
            case 500 : self = ConnectionStatus.Unsuccess
            case 504 : self = ConnectionStatus.TimeOut
            case -1 : self = ConnectionStatus.Cancelled
            default: self = ConnectionStatus.Unsuccess
                
            }
            
        }
    }
    
    
    
    
}

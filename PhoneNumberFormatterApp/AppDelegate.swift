//
//  AppDelegate.swift
//  PhoneNumberFormatterApp
//
//  Created by Tyler Prevost on 1/2/21.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        #if DEBUG
        // For debugging purposes
        let format = PhoneNumberFormatter.shared
        //format.dump()
        
        var callingCode = format.callingCode(forCountryCode: "US")
        print("US =", callingCode ?? "nil")
        callingCode = format.callingCode(forCountryCode: "AU")
        print("AU =", callingCode ?? "nil")
        
        let countries = format.countryCodes(forCallingCode: "1")
        print("countries for +1 are:", countries)
        #endif
        
        return true
    }
    
    // MARK: UISceneSession Lifecycle
    
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}

//
//  FindlyApp.swift
//
//  Created by Lingling on 8/28/25.
//
import SwiftUI
import GoogleMobileAds
import AppTrackingTransparency
import AdSupport

@main
struct FindlyApp: App {
    @StateObject private var adMobManager = AdMobManager.shared
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // Segmented control styling — purple/blue brand palette
        let seg = UISegmentedControl.appearance()
        let purple = UIColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 1.0)
        seg.selectedSegmentTintColor = purple
        seg.setTitleTextAttributes([.foregroundColor: UIColor.label], for: .normal)
        seg.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        
        // Request tracking permission FIRST with delay for UI to load
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            Self.requestTrackingPermission {
                // Initialize AdMob AFTER getting permission
                AdMobManager.shared.initialize()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ScreenSplashView()
                .environmentObject(adMobManager)
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        // Show interstitial ad when app becomes active
                        adMobManager.showInterstitialAdWithDelay(1.0)
                    }
                }
        }
    }

    
    static func requestTrackingPermission(completion: @escaping () -> Void) {
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { status in
                switch status {
                case .authorized:
                    print("✅ Tracking authorized")
                case .denied:
                    print("❌ Tracking denied")
                case .notDetermined:
                    print("⚠️ Not determined")
                case .restricted:
                    print("🚫 Restricted")
                @unknown default:
                    break
                }
                // Call completion AFTER user responds to prompt
                DispatchQueue.main.async {
                    completion()
                }
            }
        } else {
            // iOS 13 or earlier - no ATT needed
            completion()
        }
    }
}

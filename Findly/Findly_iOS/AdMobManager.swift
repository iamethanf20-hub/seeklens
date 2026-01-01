//
//  AdMobManager.swift
//  Findly
//
//  Created by Lingling on 10/24/25.
//

import GoogleMobileAds
import SwiftUI
import AppTrackingTransparency

@MainActor
final class AdMobManager: NSObject, ObservableObject {
    static let shared = AdMobManager()
    @Published var isInitialized = false
    @Published var interstitialAd: InterstitialAd?
    @Published var isInterstitialReady = false
    
    #if DEBUG
    private let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"  // Google's test interstitial
    #else
    private let interstitialAdUnitID = "ca-app-pub-2820235817467830/4381192192"  // Replace with your real ad unit ID from AdMob
    #endif
    
    private override init() {
        super.init()
    }
    
    func initialize() {
        guard !isInitialized else {
            print("⚠️ AdMob already initialized")
            return
        }
        
        // Check if Info.plist has the App ID
        if let appID = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String {
            print("✅ Found AdMob App ID in Info.plist: \(appID)")
        } else {
            print("❌ GADApplicationIdentifier NOT found in Info.plist!")
        }
        
        #if DEBUG
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = [
            "SIMULATOR",
        ]
        print("🧪 Test device identifiers set for DEBUG mode")
        #endif
        
        // Request tracking permission for iOS 14+
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { status in
                print("📊 Tracking status: \(status.rawValue)")
                switch status {
                case .authorized:
                    print("✅ Tracking authorized")
                case .denied:
                    print("❌ Tracking denied")
                case .restricted:
                    print("⚠️ Tracking restricted")
                case .notDetermined:
                    print("⏳ Tracking not determined")
                @unknown default:
                    print("❓ Unknown tracking status")
                }
                
                DispatchQueue.main.async {
                    self.startAdMob()
                }
            }
        } else {
            startAdMob()
        }
    }
    
    private func startAdMob() {
        print("🚀 Starting AdMob initialization...")
        MobileAds.shared.start { [weak self] status in
            DispatchQueue.main.async {
                self?.isInitialized = true
                print("✅ AdMob initialized successfully")
                print("📋 Adapter statuses:")
                for (adapter, adapterStatus) in status.adapterStatusesByClassName {
                    print("  - \(adapter): \(adapterStatus.state.rawValue)")
                }
                
                // Load first interstitial ad after initialization
                Task {
                    await self?.loadInterstitialAd()
                }
            }
        }
    }
    
    // MARK: - Interstitial Ad Methods
    
    func loadInterstitialAd() async {
        guard isInitialized else {
            print("⚠️ AdMob not initialized yet, cannot load interstitial")
            return
        }
        
        do {
            print("🎯 Loading interstitial ad with ID: \(interstitialAdUnitID)")
            interstitialAd = try await InterstitialAd.load(
                with: interstitialAdUnitID,  // ✅ Correct
                request: Request()
            )
            interstitialAd?.fullScreenContentDelegate = self
            isInterstitialReady = true
            print("✅ Interstitial ad loaded successfully")
        } catch {
            print("❌ Failed to load interstitial ad: \(error.localizedDescription)")
            isInterstitialReady = false
            
            // Retry after 30 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                Task {
                    await self.loadInterstitialAd()
                }
            }
        }
    }
    
    func showInterstitialAd() {
        guard isInterstitialReady, let ad = interstitialAd else {
            print("⚠️ Cannot show interstitial: ad not ready")
            // Try to load an ad for next time
            Task {
                await loadInterstitialAd()
            }
            return
        }
        
        guard let rootVC = UIApplication.shared.keyWindowPresentedController else {
            print("⚠️ Cannot show interstitial: rootVC not available")
            return
        }
        
        // Check if user is subscribed (if you have SubscriptionManager)
        // Uncomment this if you're using the SubscriptionManager from Monetization.swift
        /*
        guard !SubscriptionManager.shared.isSubscribed else {
            print("⚠️ User is subscribed, skipping ad")
            return
        }
        */
        
        print("📱 Presenting interstitial ad")
        ad.present(from: rootVC)
        isInterstitialReady = false
    }
    
    /// Show interstitial with a custom delay (useful for app launch)
    func showInterstitialAdWithDelay(_ delay: TimeInterval = 0.5) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.showInterstitialAd()
        }
    }
}

// MARK: - FullScreenContentDelegate

extension AdMobManager: FullScreenContentDelegate {
    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        print("📊 Interstitial ad recorded impression")
    }
    
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("❌ Interstitial ad failed to present: \(error.localizedDescription)")
        isInterstitialReady = false
        // Load a new ad
        Task {
            await loadInterstitialAd()
        }
    }
    
    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("📱 Interstitial ad will present full screen")
    }
    
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("📱 Interstitial ad was dismissed")
        isInterstitialReady = false
        // Load a new ad for next time
        Task {
            await loadInterstitialAd()
        }
    }
}

// MARK: - UIApplication Helper

private extension UIApplication {
    var keyWindowPresentedController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController?
            .topMost()
    }
}

private extension UIViewController {
    func topMost() -> UIViewController {
        if let presented = presentedViewController { return presented.topMost() }
        if let nav = self as? UINavigationController { return nav.visibleViewController?.topMost() ?? nav }
        if let tab = self as? UITabBarController { return tab.selectedViewController?.topMost() ?? tab }
        return self
    }
}

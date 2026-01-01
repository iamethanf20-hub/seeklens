//
//  Monetization.swift
//  Findly
//
//  Created by Lingling on 10/13/25.
//

import SwiftUI
import StoreKit

// MARK: - Constants

enum Paywall {
    static let monthlyProductID = "findly.sub.monthly"
    static let freeTextQuotaPerMonth = 300      // <- text (OCR)
    static let freeObjectQuotaPerMonth = 30     // <- object (OWL)
}

// MARK: - Usage Meter (monthly quota)

final class UsageMeter: ObservableObject {
    static let shared = UsageMeter()   // easy global access

    @AppStorage("ocrUsesThisMonth") private var ocrUsesThisMonth: Int = 0
    @AppStorage("owlUsesThisMonth") private var owlUsesThisMonth: Int = 0
    @AppStorage("quotaMonthKey") private var quotaMonthKey: String = ""

    @Published var remainingText: Int = Paywall.freeTextQuotaPerMonth
    @Published var remainingObjects: Int = Paywall.freeObjectQuotaPerMonth

    init() {
        refreshMonthIfNeeded()
    }

    func refreshMonthIfNeeded() {
        let key = Self.monthKey(for: Date())
        if quotaMonthKey != key {
            quotaMonthKey = key
            ocrUsesThisMonth = 0
            owlUsesThisMonth = 0
        }
        remainingText = max(0, Paywall.freeTextQuotaPerMonth - ocrUsesThisMonth)
        remainingObjects = max(0, Paywall.freeObjectQuotaPerMonth - owlUsesThisMonth)
    }

    /// Consume one **text (OCR)** detection. Returns `true` if allowed.
    func consumeTextDetection() -> Bool {
        refreshMonthIfNeeded()
        guard remainingText > 0 else { return false }
        ocrUsesThisMonth += 1
        remainingText = max(0, Paywall.freeTextQuotaPerMonth - ocrUsesThisMonth)
        return true
    }

    /// Consume one **object (OWL)** detection. Returns `true` if allowed.
    func consumeObjectDetection() -> Bool {
        refreshMonthIfNeeded()
        guard remainingObjects > 0 else { return false }
        owlUsesThisMonth += 1
        remainingObjects = max(0, Paywall.freeObjectQuotaPerMonth - owlUsesThisMonth)
        return true
    }

    private static func monthKey(for date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        return String(format: "%04d-%02d", y, m)   // e.g. "2025-11"
    }
}

// MARK: - StoreKit 2 Subscription Manager

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    @Published var isSubscribed: Bool = false
    @Published var products: [Product] = []
    @Published var loading = false
    @Published var error: String? = nil

    private init() {
        Task { await self.bootstrap() }
    }

    func bootstrap() async {
        await loadProducts()
        await updateEntitlements()
        // Listen for entitlement changes
        Task.detached { [weak self] in
            for await _ in Transaction.updates {
                await self?.updateEntitlements()
            }
        }
    }

    func loadProducts() async {
        loading = true
        defer { loading = false }
        do {
            let ids = [Paywall.monthlyProductID]
            products = try await Product.products(for: ids)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateEntitlements() async {
        do {
            var active = false
            for await result in Transaction.currentEntitlements {
                if case .verified(let tx) = result, tx.productType == .autoRenewable {
                    active = true
                }
            }
            self.isSubscribed = active
        }
    }

    func purchaseMonthly() async {
        guard let product = products.first(where: { $0.id == Paywall.monthlyProductID }) else { return }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    await tx.finish()
                    await updateEntitlements()
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await updateEntitlements()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Ad Banner (AdMob, SDK 12.x)

#if canImport(GoogleMobileAds)
import GoogleMobileAds

/// Single-use banner view. Uses the new 12.x symbols.
struct AdMobBannerView: UIViewRepresentable {
    #if DEBUG
    private let adUnitID = "ca-app-pub-3940256099942544/2934735716"  // Google's test banner
    #else
    private let adUnitID = "ca-app-pub-2820235817467830/8665250278"  // Your real ad unit
    #endif

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> BannerView {
        print("🎯 Creating AdMob banner view")
        print("🎯 isSubscribed: \(SubscriptionManager.shared.isSubscribed)")
        print("🎯 adMobManager.isInitialized: \(AdMobManager.shared.isInitialized)")
        
        #if DEBUG
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = [
            "SIMULATOR",
        ]
        #endif

        let view = BannerView(adSize: AdSizeBanner) // 320x50
        view.adUnitID = adUnitID
        view.delegate = context.coordinator
        view.rootViewController = UIApplication.shared.keyWindowPresentedController
        
        print("🎯 Ad Unit ID: \(adUnitID)")
        print("🎯 Root VC: \(String(describing: view.rootViewController))")
        print("🎯 Loading ad request...")
        
        view.load(Request())
        return view
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}
    
    class Coordinator: NSObject, BannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            print("✅✅✅ Ad loaded successfully!")
        }
        
        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            print("❌❌❌ Ad failed to load: \(error.localizedDescription)")
        }
        
        func bannerViewWillPresentScreen(_ bannerView: BannerView) {
            print("📱 Ad will present screen")
        }
        
        func bannerViewWillDismissScreen(_ bannerView: BannerView) {
            print("📱 Ad will dismiss screen")
        }
        
        func bannerViewDidDismissScreen(_ bannerView: BannerView) {
            print("📱 Ad did dismiss screen")
        }
    }
}

/// SwiftUI helper that hides ads for subscribers.
struct AdBannerSection: View {
    @ObservedObject private var iap = SubscriptionManager.shared
    @ObservedObject private var adMob = AdMobManager.shared

    var body: some View {
        Group {
            if !iap.isSubscribed && adMob.isInitialized {
                AdMobBannerView()
                    .frame(height: 50)
                    .accessibilityIdentifier("admob_banner")
            }
        }
        .onAppear {
            Task { await iap.updateEntitlements() }
        }
    }
}

// Helpers to find the top-most controller for AdMob
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

#else
/// Safe placeholder so your app compiles without the AdMob SDK.
struct AdMobBannerView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.15))
            .frame(height: 50)
            .overlay(Text("Ad (Connect AdMob)").font(.caption).foregroundColor(.secondary))
    }
}

/// Mirror the API so call sites don't change.
struct AdBannerSection: View {
    var body: some View { AdMobBannerView() }
}
#endif

//
//  Paywall.swift
//  Findly
//
//  Created by Lingling on 10/13/25.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var iap = SubscriptionManager.shared
    @ObservedObject var usage = UsageMeter.shared   // <- use shared meter

    var body: some View {
        VStack(spacing: 16) {
            // Header
            Text("SeekLens Premium")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
            Text("Unlimited text & object detection • No ads")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            // Price row
            if let product = iap.products.first(where: { $0.id == Paywall.monthlyProductID }) {
                Text(product.displayPrice + " / month")
                    .font(.title3).bold()
            } else {
                Text("$0.99 / month")
                    .font(.title3).bold()
            }

            // Current status
            Group {
                if iap.isSubscribed {
                    Label("You're subscribed! Unlimited text & objects.", systemImage: "checkmark.seal.fill")
                        .foregroundColor(.green)
                } else {
                    Label(
                        "\(usage.remainingText) text & \(usage.remainingObjects) object detections left this month",
                        systemImage: "clock"
                    )
                    .foregroundColor(.secondary)
                }
            }
            .padding(.top, 8)

            // CTA buttons
            VStack(spacing: 10) {
                Button {
                    Task { await iap.purchaseMonthly() }
                } label: {
                    HStack {
                        Image(systemName: "seal")
                        Text("Start Premium")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Restore Purchases") {
                    Task { await iap.restore() }
                }

                Button("Not now") { dismiss() }
                    .foregroundColor(.secondary)
            }
            .padding(.top, 10)

            Spacer()
            
            // REQUIRED: Privacy Policy and Terms of Use links
            HStack(spacing: 15) {
                Link("Privacy Policy", destination: URL(string: "https://iamethanf20-hub.github.io/fiddly-privacy-support/")!)
                    .font(.caption)
                    .foregroundColor(.blue)
                
                Text("•")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Link("Terms of Use", destination: URL(string: "https://iamethanf20-hub.github.io/fiddly-privacy-support/")!)
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .padding(.bottom, 4)
            
            // Tiny legal
            Text("Auto-renewing. Cancel anytime in Settings.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

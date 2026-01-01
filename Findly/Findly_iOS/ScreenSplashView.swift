//
//  ScreenSplashView.swift
//  Findly
//
//  Created by Lingling on 9/11/25.
//

import SwiftUI

struct ScreenSplashView: View {
    @State private var showMainSplash = true
    @State private var showWarningSplash = false
    @State private var animateLogo = false
    @State private var animateWarning = false

    var body: some View {
        ZStack {
            ContentView()
                .opacity((showMainSplash || showWarningSplash) ? 0 : 1)

            if showMainSplash {
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()

                    VStack(spacing: 12) {
                        Image("SplashLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 160)
                            .scaleEffect(animateLogo ? 1.0 : 0.4)
                            .opacity(animateLogo ? 1.0 : 0.0)
                            .animation(.interpolatingSpring(stiffness: 150, damping: 9).delay(0.1), value: animateLogo)

                        Text("SeekLens")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .scaleEffect(animateLogo ? 1.0 : 0.6)
                            .opacity(animateLogo ? 1.0 : 0.0)
                            .animation(.interpolatingSpring(stiffness: 140, damping: 10).delay(0.25), value: animateLogo)
                    }
                }
                .onAppear {
                    withAnimation {
                        animateLogo = true
                    }

                    // After first splash, show warning screen
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            showMainSplash = false
                            showWarningSplash = true
                        }
                    }
                }
            }

            if showWarningSplash {
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()

                    VStack(spacing: 16) {
                        Text("Important")
                            .font(.headline)
                            .opacity(animateWarning ? 1.0 : 0.0)
                            .scaleEffect(animateWarning ? 1.0 : 0.9)

                        Text("SeekLens is not always accurate.\nPlease double-check predictions.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .opacity(animateWarning ? 1.0 : 0.0)
                            .scaleEffect(animateWarning ? 1.0 : 0.9)
                    }
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        animateWarning = true
                    }

                    // Hide warning and show app
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            showWarningSplash = false
                        }
                    }
                }
            }
        }
    }
}

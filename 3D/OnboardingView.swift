//
//  OnboardingView.swift
//  3D
//
//  Beautiful onboarding with animated instructions
//

import SwiftUI

struct OnboardingView: View {
    @Binding var showOnboarding: Bool
    @State private var currentPage = 0

    let pages: [(icon: String, title: String, description: String, color: Color)] = [
        ("cube.transparent", "3D Scanner", "Erstelle hochwertige 3D-Modelle von realen Objekten mit deinem iPhone.", .blue),
        ("camera.viewfinder", "Objekt erfassen", "Richte die Kamera auf dein Objekt. Die KI erkennt es automatisch.", .green),
        ("arrow.triangle.2.circlepath", "Umkreisen", "Gehe langsam um das Objekt herum. Die App führt dich dabei.", .orange),
        ("sparkles", "Fertig!", "Dein 3D-Modell wird automatisch erstellt und kann in AR betrachtet werden.", .purple)
    ]

    var body: some View {
        ZStack {
            // Animated gradient background
            LinearGradient(
                colors: [
                    pages[currentPage].color.opacity(0.3),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: currentPage)

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button("Überspringen") {
                        withAnimation {
                            showOnboarding = false
                        }
                    }
                    .foregroundColor(.white.opacity(0.6))
                    .padding()
                }

                Spacer()

                // Icon with animation
                ZStack {
                    Circle()
                        .fill(pages[currentPage].color.opacity(0.2))
                        .frame(width: 180, height: 180)

                    Circle()
                        .fill(pages[currentPage].color.opacity(0.3))
                        .frame(width: 140, height: 140)

                    Image(systemName: pages[currentPage].icon)
                        .font(.system(size: 60))
                        .foregroundColor(pages[currentPage].color)
                        .symbolEffect(.pulse)
                }
                .animation(.easeInOut(duration: 0.5), value: currentPage)

                Spacer()
                    .frame(height: 60)

                // Title & Description
                VStack(spacing: 16) {
                    Text(pages[currentPage].title)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)

                    Text(pages[currentPage].description)
                        .font(.system(size: 17))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                Spacer()

                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? pages[currentPage].color : Color.white.opacity(0.3))
                            .frame(width: index == currentPage ? 10 : 8, height: index == currentPage ? 10 : 8)
                            .animation(.easeInOut(duration: 0.3), value: currentPage)
                    }
                }
                .padding(.bottom, 30)

                // Action button
                Button(action: {
                    withAnimation {
                        if currentPage < pages.count - 1 {
                            currentPage += 1
                        } else {
                            showOnboarding = false
                        }
                    }
                }) {
                    HStack(spacing: 12) {
                        Text(currentPage < pages.count - 1 ? "Weiter" : "Los geht's")
                            .font(.system(size: 18, weight: .semibold))

                        Image(systemName: currentPage < pages.count - 1 ? "arrow.right" : "camera.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(pages[currentPage].color)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 50)
            }
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width < -50 && currentPage < pages.count - 1 {
                        withAnimation { currentPage += 1 }
                    } else if value.translation.width > 50 && currentPage > 0 {
                        withAnimation { currentPage -= 1 }
                    }
                }
        )
    }
}

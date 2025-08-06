//
//  RUNSTR_IOSApp.swift
//  RUNSTR IOS
//
//  Created by Dakota Brown on 7/25/25.
//

import SwiftUI

@main
struct RUNSTR_IOSApp: App {
    @StateObject private var authService = AuthenticationService()
    @StateObject private var healthKitService = HealthKitService()
    @StateObject private var locationService = LocationService()
    @StateObject private var workoutSession = WorkoutSession()
    @StateObject private var subscriptionService = SubscriptionService()
    @StateObject private var nostrService = NostrService()
    @StateObject private var cashuService = CashuService()
    @StateObject private var streakService = StreakService()
    @StateObject private var workoutStorage = WorkoutStorage()
    
    init() {
        // Configuration will be done in onAppear
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                .environmentObject(healthKitService)
                .environmentObject(locationService)
                .environmentObject(workoutSession)
                .environmentObject(subscriptionService)
                .environmentObject(nostrService)
                .environmentObject(cashuService)
                .environmentObject(streakService)
                .environmentObject(workoutStorage)
                .preferredColorScheme(.dark)
                .task {
                    // Configure workout session with services first
                    workoutSession.configure(
                        healthKitService: healthKitService,
                        locationService: locationService
                    )
                    
                    // Configure authentication service with NostrService reference
                    authService.configureNostrService(nostrService)
                    
                    // Request permissions on app startup
                    await requestInitialPermissions()
                    
                    // Initialize Cashu connection
                    await cashuService.connectToMint()
                }
        }
    }
    
    @MainActor
    private func requestInitialPermissions() async {
        // Request HealthKit authorization
        let _ = await healthKitService.requestAuthorization()
        
        // Request location permission
        locationService.requestLocationPermission()
        
        print("✅ Initial permissions requested")
    }
}

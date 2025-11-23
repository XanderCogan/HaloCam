//
//  DroneController.swift
//

import Foundation
#if !targetEnvironment(simulator)
import DJISDK
#endif

final class DroneController {
    
    /// Called when a command starts executing
    var onCommandStarted: ((DroneIntent) -> Void)?
    
    /// Called when a command completes executing
    /// Parameters: (intent: DroneIntent, error: Error?)
    var onCommandCompleted: ((DroneIntent, Error?) -> Void)?
    
    /// Photo downloader instance
    private let photoDownloader = PhotoDownloader()
    
    /// Track the last camera mode so we can restore it after download
    private var lastCameraMode: DJICameraMode?
    
    init() {
        setupPhotoDownloader()
        setupCameraDelegate()
    }
    
    // MARK: - Public entry point from voice layer
    
    func handle(intent: DroneIntent) {
        switch intent {
        case .takeOff:
            startTakeoff()
            
        case .land:
            startLanding()
            
        case .takePhoto:
            takePhotoOnce()
            
        case .photoPosition:
            runPhotoPositionRoutine()
        }
    }
    
    // MARK: - Basic actions
    
    private func startTakeoff() {
        DispatchQueue.main.async {
            self.onCommandStarted?(.takeOff)
        }
        
        #if !targetEnvironment(simulator)
        guard let aircraft = DJISDKManager.product() as? DJIAircraft,
              let fc = aircraft.flightController else {
            print("No aircraft / flight controller")
            DispatchQueue.main.async {
                self.onCommandCompleted?(.takeOff, NSError(domain: "DroneController", code: -1, userInfo: [NSLocalizedDescriptionKey: "No aircraft / flight controller"]))
            }
            return
        }
        
        fc.startTakeoff { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Takeoff error: \(error.localizedDescription)")
                    self.onCommandCompleted?(.takeOff, error)
                } else {
                    print("Takeoff started")
                    self.onCommandCompleted?(.takeOff, nil)
                }
            }
        }
        #else
        print("Takeoff (simulator)")
        DispatchQueue.main.async {
            self.onCommandCompleted?(.takeOff, nil)
        }
        #endif
    }
    
    private func startLanding() {
        DispatchQueue.main.async {
            self.onCommandStarted?(.land)
        }
        
        #if !targetEnvironment(simulator)
        guard let aircraft = DJISDKManager.product() as? DJIAircraft,
              let fc = aircraft.flightController else {
            print("No aircraft / flight controller")
            DispatchQueue.main.async {
                self.onCommandCompleted?(.land, NSError(domain: "DroneController", code: -1, userInfo: [NSLocalizedDescriptionKey: "No aircraft / flight controller"]))
            }
            return
        }
        
        fc.startLanding { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Landing error: \(error.localizedDescription)")
                    self.onCommandCompleted?(.land, error)
                } else {
                    print("Landing started")
                    self.onCommandCompleted?(.land, nil)
                }
            }
        }
        #else
        print("Landing (simulator)")
        DispatchQueue.main.async {
            self.onCommandCompleted?(.land, nil)
        }
        #endif
    }
    
    private func takePhotoOnce() {
        DispatchQueue.main.async {
            self.onCommandStarted?(.takePhoto)
        }
        
        #if !targetEnvironment(simulator)
        guard let aircraft = DJISDKManager.product() as? DJIAircraft,
              let camera = aircraft.camera else {
            print("No aircraft / camera")
            DispatchQueue.main.async {
                self.onCommandCompleted?(.takePhoto, NSError(domain: "DroneController", code: -1, userInfo: [NSLocalizedDescriptionKey: "No aircraft / camera"]))
            }
            return
        }
        
        // Ensure camera is in photo mode
        camera.setMode(.shootPhoto) { error in
            if let error = error {
                print("setMode error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.onCommandCompleted?(.takePhoto, error)
                }
                return
            }
            
            camera.startShootPhoto { error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("startShootPhoto error: \(error.localizedDescription)")
                        self.onCommandCompleted?(.takePhoto, error)
                    } else {
                        print("Photo captured")
                        self.onCommandCompleted?(.takePhoto, nil)
                    }
                }
            }
        }
        #else
        print("Take photo (simulator)")
        DispatchQueue.main.async {
            self.onCommandCompleted?(.takePhoto, nil)
        }
        #endif
    }
    
    // MARK: - Hard-coded "photo position" script
    
    /// Voice command: "photo position"
    /// Script:
    ///  - Take off
    ///  - Climb to ~3m
    ///  - Take a single photo
    ///  - Then hover
    private func runPhotoPositionRoutine() {
        DispatchQueue.main.async {
            self.onCommandStarted?(.photoPosition)
        }
        
        #if !targetEnvironment(simulator)
        guard let missionControl = DJISDKManager.missionControl() else {
            print("MissionControl unavailable")
            DispatchQueue.main.async {
                self.onCommandCompleted?(.photoPosition, NSError(domain: "DroneController", code: -1, userInfo: [NSLocalizedDescriptionKey: "MissionControl unavailable"]))
            }
            return
        }
        
        // Get current altitude to calculate target altitude
        // Default to 4.5m to ensure we go above typical table height (1.5m) + 3m target
        var targetAltitude: Double = 4.5
        if let aircraft = DJISDKManager.product() as? DJIAircraft,
           let fc = aircraft.flightController {
            // Try to access current altitude from flight controller state using KVC
            // This works across different DJI SDK versions
            if let state = fc.value(forKey: "state") as? DJIFlightControllerState {
                let currentAltitude = state.altitude
                // Calculate target altitude: ensure at least 3.0m from takeoff point
                // If already above 3m, add 3m more; otherwise go to 3m
                targetAltitude = max(currentAltitude + 3.0, 3.0)
                print("Current altitude: \(currentAltitude)m, Target altitude: \(targetAltitude)m")
            } else {
                // Fallback: use 4.5m to ensure we go above table height + reach 3m target
                print("Could not access flight controller state, using default target altitude: \(targetAltitude)m")
            }
        }
        
        // Stop and clear previous timeline if any
        missionControl.stopTimeline()
        missionControl.unscheduleAllElements()
        
        var elements: [DJIMissionControlTimelineElement] = []
        
        // 1) Takeoff
        let takeoff = DJITakeOffAction()
        elements.append(takeoff)
        
        // 2) Go to target altitude (meters, absolute altitude relative to takeoff point)
        let goToAltitude = DJIGoToAction(altitude: targetAltitude)
        elements.append(goToAltitude)
        
        // 3) Take a single photo
        let shootPhotoAction = DJIShootPhotoAction()
        elements.append(shootPhotoAction)
        
        missionControl.scheduleElements(elements)
        missionControl.startTimeline()
        
        // Note: Timeline execution is asynchronous and doesn't provide a simple completion callback
        // For now, we'll mark it as started. A more sophisticated implementation would track timeline state.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Assume success after a short delay (timeline started successfully)
            // In a real implementation, you'd want to listen to timeline state changes
            self.onCommandCompleted?(.photoPosition, nil)
        }
        #else
        print("Photo position routine (simulator)")
        DispatchQueue.main.async {
            self.onCommandCompleted?(.photoPosition, nil)
        }
        #endif
    }
    
    // MARK: - Photo Download Setup
    
    private func setupPhotoDownloader() {
        photoDownloader.onPhotoSaved = { [weak self] error in
            if let error = error {
                print("Photo save error: \(error.localizedDescription)")
            } else {
                print("Photo saved to library successfully")
            }
        }
    }
    
    private func setupCameraDelegate() {
        #if !targetEnvironment(simulator)
        // Set up camera delegate when product connects
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(productConnected),
            name: .productConnected,
            object: nil
        )
        #endif
    }
    
    @objc private func productConnected() {
        #if !targetEnvironment(simulator)
        guard let aircraft = DJISDKManager.product() as? DJIAircraft,
              let camera = aircraft.camera else {
            return
        }
        camera.delegate = self
        print("Camera delegate set")
        #endif
    }
}

// MARK: - DJICameraDelegate

#if !targetEnvironment(simulator)
extension DroneController: DJICameraDelegate {
    
    func camera(_ camera: DJICamera, didGenerateNewMediaFile newMedia: DJIMediaFile) {
        print("New media file generated: \(newMedia.fileName ?? "unknown")")
        
        // Only process JPEG photos
        guard newMedia.mediaType == .JPEG else {
            print("Skipping non-JPEG media: \(newMedia.mediaType.rawValue)")
            return
        }
        
        // Download and save the photo
        downloadAndSavePhoto(mediaFile: newMedia)
    }
    
    private func downloadAndSavePhoto(mediaFile: DJIMediaFile) {
        guard let aircraft = DJISDKManager.product() as? DJIAircraft,
              let camera = aircraft.camera else {
            print("No camera available for download")
            return
        }
        
        // Save current camera mode
        camera.getModeWithCompletion { [weak self] mode, error in
            guard let self = self else { return }
            
            if let mode = mode {
                self.lastCameraMode = mode
            }
            
            // Switch to MediaDownload mode if not already
            if mode != .mediaDownload {
                camera.setMode(.mediaDownload) { error in
                    if let error = error {
                        print("Failed to switch to MediaDownload mode: \(error.localizedDescription)")
                        // Try downloading anyway - some cameras might work
                        self.photoDownloader.downloadAndSavePhoto(mediaFile: mediaFile)
                    } else {
                        print("Switched to MediaDownload mode")
                        // Download the photo
                        self.photoDownloader.downloadAndSavePhoto(mediaFile: mediaFile)
                        
                        // Restore previous mode after a delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            if let previousMode = self.lastCameraMode {
                                camera.setMode(previousMode) { error in
                                    if let error = error {
                                        print("Failed to restore camera mode: \(error.localizedDescription)")
                                    } else {
                                        print("Restored camera mode to \(previousMode.rawValue)")
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                // Already in MediaDownload mode
                self.photoDownloader.downloadAndSavePhoto(mediaFile: mediaFile)
            }
        }
    }
}
#endif


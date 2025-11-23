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
        
        // Stop and clear previous timeline if any
        missionControl.stopTimeline()
        missionControl.unscheduleAllElements()
        
        var elements: [DJIMissionControlTimelineElement] = []
        
        // 1) Takeoff
        let takeoff = DJITakeOffAction()
        elements.append(takeoff)
        
        // 2) Go to fixed altitude (meters, relative to takeoff)
        let goToAltitude = DJIGoToAction(altitude: 3.0)
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
}


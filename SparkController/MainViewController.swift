import UIKit
#if !targetEnvironment(simulator)
import DJISDK
#endif

class MainViewController: UIViewController {

    #if targetEnvironment(simulator)
    private var isSimulatedConnected = false
    private var isFlying = false
    #endif

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "Disconnected"
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textColor = .systemRed
        return label
    }()

    private let takeoffButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("TAKEOFF", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 24, weight: .bold)
        button.backgroundColor = .systemGreen
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        return button
    }()

    private let landButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("LAND", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 24, weight: .bold)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNotifications()

        #if targetEnvironment(simulator)
        // Auto-connect in simulator after 1 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.simulateConnection()
        }
        #endif
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        #if targetEnvironment(simulator)
        let simLabel = UILabel()
        simLabel.text = "SIMULATOR MODE"
        simLabel.font = .systemFont(ofSize: 12, weight: .bold)
        simLabel.textColor = .systemOrange
        simLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [simLabel, statusLabel, takeoffButton, landButton])
        #else
        let stack = UIStackView(arrangedSubviews: [statusLabel, takeoffButton, landButton])
        #endif

        stack.axis = .vertical
        stack.spacing = 30
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            takeoffButton.widthAnchor.constraint(equalToConstant: 200),
            takeoffButton.heightAnchor.constraint(equalToConstant: 60),
            landButton.widthAnchor.constraint(equalToConstant: 200),
            landButton.heightAnchor.constraint(equalToConstant: 60)
        ])

        takeoffButton.addTarget(self, action: #selector(takeoff), for: .touchUpInside)
        landButton.addTarget(self, action: #selector(land), for: .touchUpInside)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(productConnected), name: .productConnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(productDisconnected), name: .productDisconnected, object: nil)
    }

    #if targetEnvironment(simulator)
    private func simulateConnection() {
        isSimulatedConnected = true
        statusLabel.text = "Connected: Spark (Simulated)"
        statusLabel.textColor = .systemGreen
    }
    #endif

    @objc private func productConnected(_ notification: Notification) {
        DispatchQueue.main.async {
            #if targetEnvironment(simulator)
            self.statusLabel.text = "Connected: Spark (Simulated)"
            #else
            let product = notification.object as? DJIBaseProduct
            self.statusLabel.text = "Connected: \(product?.model ?? "Aircraft")"
            #endif
            self.statusLabel.textColor = .systemGreen
        }
    }

    @objc private func productDisconnected() {
        DispatchQueue.main.async {
            self.statusLabel.text = "Disconnected"
            self.statusLabel.textColor = .systemRed
        }
    }

    #if !targetEnvironment(simulator)
    private var flightController: DJIFlightController? {
        let aircraft = DJISDKManager.product() as? DJIAircraft
        return aircraft?.flightController
    }
    #endif

    @objc private func takeoff() {
        #if targetEnvironment(simulator)
        guard isSimulatedConnected else {
            showAlert("Not Connected", message: "Connect to your Spark first")
            return
        }
        if isFlying {
            showAlert("Already Flying", message: "Spark is already in the air")
            return
        }
        isFlying = true
        showAlert("Takeoff", message: "Spark is taking off! (Simulated)")
        #else
        guard let fc = flightController else {
            showAlert("Not Connected", message: "Connect to your Spark first")
            return
        }

        fc.startTakeoff { error in
            DispatchQueue.main.async {
                if let error = error {
                    self.showAlert("Takeoff Failed", message: error.localizedDescription)
                } else {
                    self.showAlert("Takeoff", message: "Spark is taking off!")
                }
            }
        }
        #endif
    }

    @objc private func land() {
        #if targetEnvironment(simulator)
        guard isSimulatedConnected else {
            showAlert("Not Connected", message: "Connect to your Spark first")
            return
        }
        if !isFlying {
            showAlert("Not Flying", message: "Spark is already on the ground")
            return
        }
        isFlying = false
        showAlert("Landing", message: "Spark is landing! (Simulated)")
        #else
        guard let fc = flightController else {
            showAlert("Not Connected", message: "Connect to your Spark first")
            return
        }

        fc.startLanding { error in
            DispatchQueue.main.async {
                if let error = error {
                    self.showAlert("Landing Failed", message: error.localizedDescription)
                } else {
                    self.showAlert("Landing", message: "Spark is landing!")
                }
            }
        }
        #endif
    }

    private func showAlert(_ title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

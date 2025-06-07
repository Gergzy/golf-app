import UIKit
import MapKit
import CoreLocation
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth
import SwiftUI

class ViewController: UIViewController, CLLocationManagerDelegate, MKMapViewDelegate, UIPickerViewDelegate, UIPickerViewDataSource {
    
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var pickerView: UIPickerView!
    @IBOutlet weak var distanceLabel: UILabel!
    @IBOutlet weak var playsLikeLabel: UILabel!
    @IBOutlet weak var recommendationLabel: UILabel!

    private var sidebarViewController: SidebarViewController?
    private var isSidebarVisible = false
    private let sidebarWidth: CGFloat = 250
    private var shouldSkipAuthCheck = false

    // Actions
    @IBAction func startShot(_ sender: UIButton) {
        guard let location = locationManager.location else { return }
        startLocation = location
        distanceLabel.text = "Distance: Shot started"
        playsLikeLabel.text = "Plays Like: Shot started"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.updateDistanceToHole()
        }
    }

    @IBAction func endShot(_ sender: UIButton) {
        guard let start = startLocation, let end = locationManager.location else { return }
        let distance = start.distance(from: end)
        let club = items[pickerView.selectedRow(inComponent: 0)]
        let shot = Shot(club: club, distance: distance)
        shots.append(shot)
        userStatusViewModel.fetchUserStatus()
        saveShots()
        distanceLabel.text = String(format: "Distance: %.1f yards", distance * 1.09361)
        playsLikeLabel.text = "Plays Like: N/A"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.updateDistanceToHole()
        }
        startLocation = nil
        print("End shot called, isLoggedIn = \(userStatusViewModel.isLoggedIn), uid = \(userStatusViewModel.currentUser?.uid ?? "nil")")
    }

    @IBAction func recommendClub(_ sender: UIButton) {
        guard let currentLocation = locationManager.location else {
            recommendationLabel.text = "Recommendation: Location unavailable"
            return
        }
        let holeLocation = CLLocation(latitude: holeCoordinate.latitude, longitude: holeCoordinate.longitude)
        let distance = currentLocation.distance(from: holeLocation) * 1.09361
        let club = recommendClub(forDistance: distance)
        recommendationLabel.text = "Recommendation: \(club)"
    }

    @IBAction func toggleSidebar(_ sender: UIBarButtonItem) {
        isSidebarVisible.toggle()
        if isSidebarVisible {
            showSidebar()
        } else {
            hideSidebar()
        }
    }

    // Properties
    let db = Firestore.firestore()
    let locationManager = CLLocationManager()
    var holeCoordinate = CLLocationCoordinate2D(latitude: 45.099087, longitude: -93.518656)
    var holeElevation: Double = 0.0 // Elevation in meters, fetched from API
    var userElevation: Double = 0.0 // Elevation in meters, fetched from API
    let items = ["Driver", "3-Wood", "5-Wood", "7-Wood", "1-Iron", "2-Iron", "3-Iron", "4-Iron", "5-Iron", "6-Iron", "7-Iron", "8-Iron", "9-Iron", "Pitching Wedge", "Gap Wedge", "Sand Wedge", "Lob Wedge"]
    let userStatusViewModel = UserStatusViewModel()
    var startLocation: CLLocation?
    var shots: [Shot] = []
    var scores: [ScoreEntry] = []

    struct Shot: Codable {
        let club: String
        let distance: Double
        var id: String?
        
        enum CodingKeys: String, CodingKey {
            case club
            case distance
            case id
        }
    }

    struct ScoreEntry: Codable {
        let course: String
        let score: Double
        let holes: [Int]
        
        enum CodingKeys: String, CodingKey {
            case course
            case score
            case holes
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        print("ViewController viewDidLoad called")
        print("View frame: \(view.frame)")
        setupMapView()
        print("MapView frame: \(mapView.frame)")
        setupLocationManager()
        print("Location manager setup completed")
        pickerView.delegate = self
        pickerView.dataSource = self
        print("PickerView frame: \(pickerView.frame)")
        distanceLabel.text = "Distance: Not measured"
        playsLikeLabel.text = "Plays Like: Not calculated"
        print("DistanceLabel set")
        recommendationLabel.text = "Recommendation: None"
        print("RecommendationLabel set")
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        mapView.addGestureRecognizer(longPress)
        print("Long press gesture added")

        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "line.horizontal.3"), style: .plain, target: self, action: #selector(toggleSidebar))
        print("Hamburger icon set")

        // Fetch initial elevation for default hole coordinate
        fetchElevation(for: holeCoordinate) { elevation in
            if let elevation = elevation {
                self.holeElevation = elevation
                print("Hole elevation set to \(elevation) meters")
                self.updateDistanceToHole()
            } else {
                print("Failed to fetch initial hole elevation, using default value")
                self.holeElevation = 0.0
                self.updateDistanceToHole()
            }
        }
    }

    func presentLoginView() {
        print("Presenting login view")
        let loginView = UIHostingController(rootView: LoginView()
            .environmentObject(userStatusViewModel)
            .onDisappear {
                print("Login view dismissed, isLoggedIn = \(self.userStatusViewModel.isLoggedIn), uid = \(self.userStatusViewModel.currentUser?.uid ?? "nil")")
                if self.userStatusViewModel.isLoggedIn, let userId = self.userStatusViewModel.currentUser?.uid {
                    self.shouldSkipAuthCheck = false
                    self.loadShots()
                    self.loadScores()
                    print("Data loaded for user: \(userId)")
                } else {
                    self.shouldSkipAuthCheck = true
                }
            })
        loginView.modalPresentationStyle = .fullScreen
        present(loginView, animated: true) {
            print("Login view presentation completed")
        }
    }

    @objc func handleLongPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
        if gestureRecognizer.state == .began {
            let touchPoint = gestureRecognizer.location(in: mapView)
            let newCoordinate = mapView.convert(touchPoint, toCoordinateFrom: mapView)
            let annotations = mapView.annotations
            mapView.removeAnnotations(annotations)
            holeCoordinate = newCoordinate
            let annotation = MKPointAnnotation()
            annotation.coordinate = holeCoordinate
            annotation.title = "Hole"
            mapView.addAnnotation(annotation)
            let region = MKCoordinateRegion(center: holeCoordinate, latitudinalMeters: 500, longitudinalMeters: 500)
            mapView.setRegion(region, animated: true)
            
            // Fetch elevation for the new hole coordinate
            fetchElevation(for: holeCoordinate) { elevation in
                if let elevation = elevation {
                    self.holeElevation = elevation
                    print("Hole elevation set to \(elevation) meters")
                } else {
                    print("Failed to fetch elevation, using default value")
                    self.holeElevation = 0.0
                }
                self.updateDistanceToHole()
            }
        }
    }

    func fetchElevation(for coordinate: CLLocationCoordinate2D, completion: @escaping (Double?) -> Void) {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_API_KEY") as? String, !apiKey.isEmpty else {
            print("API Key not found in config.xcconfig")
            if let infoDict = Bundle.main.infoDictionary {
                print("Info.plist contents: \(infoDict)")
            } else {
                print("No Info.plist dictionary available")
            }
            completion(nil)
            return
        }

        print("Using API Key: \(apiKey)")

        let cleanApiKey = apiKey.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let urlString = "https://maps.googleapis.com/maps/api/elevation/json?locations=\(coordinate.latitude),\(coordinate.longitude)&key=\(cleanApiKey)"
        print("URL: \(urlString)")

        guard let url = URL(string: urlString) else {
            print("Invalid URL for Elevation API: \(urlString)")
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("iOSApp/1.0 (Simulator)", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error fetching elevation: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let data = data else {
                print("No data received from Elevation API")
                completion(nil)
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let results = json["results"] as? [[String: Any]],
                   let firstResult = results.first,
                   let elevation = firstResult["elevation"] as? Double {
                    completion(elevation)
                } else {
                    print("Invalid JSON structure from Elevation API")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("Received JSON: \(jsonString)")
                    }
                    completion(nil)
                }
            } catch {
                print("Error parsing Elevation API response: \(error.localizedDescription)")
                completion(nil)
            }
        }

        task.resume()
    }

    func setupMapView() {
        mapView.delegate = self
        mapView.showsUserLocation = true
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        let annotation = MKPointAnnotation()
        annotation.coordinate = holeCoordinate
        annotation.title = "Hole"
        mapView.addAnnotation(annotation)
        let region = MKCoordinateRegion(center: holeCoordinate, latitudinalMeters: 500, longitudinalMeters: 500)
        mapView.setRegion(region, animated: true)
    }

    func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return items.count
    }

    func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
        let label = (view as? UILabel) ?? UILabel()
        label.text = items[row]
        label.textAlignment = .center
        label.textColor = .black
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        return label
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        print("Updated location: latitude \(location.coordinate.latitude), longitude \(location.coordinate.longitude), altitude \(location.altitude) meters, horizontalAccuracy \(location.horizontalAccuracy) meters, verticalAccuracy \(location.verticalAccuracy) meters, timestamp \(location.timestamp)")
        
        // Fetch elevation for the current user location
        fetchElevation(for: location.coordinate) { [weak self] elevation in
            if let elevation = elevation {
                self?.userElevation = elevation
                print("User elevation set to \(elevation) meters")
            } else {
                print("Failed to fetch user elevation, using default value")
                self?.userElevation = 0.0
            }
            self?.updateDistanceToHole()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let alert = UIAlertController(title: "Error", message: "Location error: \(error.localizedDescription)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func updateDistanceToHole() {
        guard let location = locationManager.location else {
            distanceLabel.text = "Distance: Location unavailable"
            playsLikeLabel.text = "Plays Like: Unavailable"
            return
        }
        let holeLocation = CLLocation(latitude: holeCoordinate.latitude, longitude: holeCoordinate.longitude)
        let distance = location.distance(from: holeLocation) * 1.09361 // Convert to yards
        
        // Calculate elevation difference with fetched user elevation
        let elevationDifferenceMeters = holeElevation - userElevation
        let elevationDifferenceFeet = elevationDifferenceMeters * 3.28084
        let elevationDifferenceYards = elevationDifferenceFeet / 3.0
        
        // Insert print statements
        print("Hole Elevation: \(holeElevation) meters")
        print("Current location elevation: \(userElevation) meters")
        print("Elevation difference: \(elevationDifferenceFeet) feet")
        
        // Adjust distance for "Plays Like"
        let adjustedDistance = distance + elevationDifferenceYards
        
        DispatchQueue.main.async {
            self.distanceLabel.text = String(format: "Distance: %.1f yards (Elev Diff: %.1f ft)", distance, elevationDifferenceFeet)
            self.playsLikeLabel.text = String(format: "Plays Like: %.1f yards", adjustedDistance)
        }
    }

    func saveShots() {
        print("saveShots called, isLoggedIn = \(userStatusViewModel.isLoggedIn), uid from viewModel = \(userStatusViewModel.currentUser?.uid ?? "nil"), auth currentUser = \(Auth.auth().currentUser?.uid ?? "nil")")
        guard let userId = userStatusViewModel.currentUser?.uid else {
            print("No user ID, cannot save shots")
            return
        }
        print("Saving shots for user: \(userId)")
        let userDocRef = db.collection("users").document(userId)
        userDocRef.getDocument { [weak self] document, error in
            if let error = error {
                print("Error fetching user document: \(error.localizedDescription)")
                return
            }
            var clubDistances: [String: [Double]] = [:]
            if let data = document?.data(), let existingDistances = data["ClubDistances"] as? [String: [Double]] {
                clubDistances = existingDistances
            }
            for shot in self?.shots ?? [] {
                var distances = clubDistances[shot.club, default: []]
                distances.append(shot.distance * 1.09361)
                clubDistances[shot.club] = distances
            }
            do {
                try userDocRef.setData(["ClubDistances": clubDistances], merge: true) { error in
                    if let error = error {
                        print("Error saving club distances: \(error.localizedDescription)")
                    } else {
                        print("Club distances saved successfully")
                        self?.shots.removeAll()
                    }
                }
            } catch {
                print("Error setting data: \(error.localizedDescription)")
            }
        }
    }

    func loadShots() {
        print("loadShots called with uid = \(userStatusViewModel.currentUser?.uid ?? "nil")")
        guard let userId = userStatusViewModel.currentUser?.uid else {
            print("No user ID, cannot load shots")
            return
        }
        print("Loading shots for user: \(userId)")
        let userDocRef = db.collection("users").document(userId)
        userDocRef.getDocument { [weak self] document, error in
            if let error = error {
                print("Error loading shots: \(error.localizedDescription)")
                return
            }
            if let data = document?.data(), let clubDistances = data["ClubDistances"] as? [String: [Double]] {
                var allShots: [Shot] = []
                for (club, distances) in clubDistances {
                    for distance in distances {
                        let shot = Shot(club: club, distance: distance / 1.09361)
                        allShots.append(shot)
                    }
                }
                self?.shots = allShots
                print("Loaded \(allShots.count) shots")
            } else {
                print("No club distances found")
            }
        }
    }

    func loadScores() {
        print("loadScores called with uid = \(userStatusViewModel.currentUser?.uid ?? "nil")")
        guard let userId = userStatusViewModel.currentUser?.uid else {
            print("No user ID, cannot load scores")
            return
        }
        print("Loading scores for user: \(userId)")
        db.collection("users").document(userId).collection("Score").getDocuments { [weak self] snapshot, error in
            if let error = error {
                print("Error loading scores: \(error.localizedDescription)")
                return
            }
            self?.scores = snapshot?.documents.compactMap { doc in
                try? doc.data(as: ScoreEntry.self)
            } ?? []
            print("Loaded \(self?.scores.count ?? 0) scores")
        }
    }

    func recommendClub(forDistance distance: Double) -> String {
        let clubAverages = shots.reduce(into: [String: [Double]]()) { dict, shot in
            dict[shot.club, default: []].append(shot.distance * 1.09361)
        }
        let averages = clubAverages.mapValues { distances in
            distances.reduce(0, +) / Double(distances.count)
        }
        let suitableClub = averages.min { abs($0.value - distance) < abs($1.value - distance) }
        return suitableClub?.key ?? "No recommendation"
    }

    func calculateHandicap() -> Double {
        let courseRating = 72.0
        let slopeRating = 113.0
        let differentials = scores.map { ($0.score - courseRating) * 113 / slopeRating }
        let lowest = differentials.sorted().prefix(3)
        return lowest.reduce(0, +) / Double(lowest.count) * 0.96
    }

    private func showSidebar() {
        guard sidebarViewController == nil else { return }
        let sidebarVC = SidebarViewController()
        sidebarVC.delegate = self
        sidebarVC.view.frame = CGRect(x: -sidebarWidth, y: 0, width: sidebarWidth, height: view.frame.height)
        view.addSubview(sidebarVC.view)
        addChild(sidebarVC)
        sidebarVC.didMove(toParent: self)
        sidebarViewController = sidebarVC

        UIView.animate(withDuration: 0.3) {
            sidebarVC.view.frame.origin.x = 0
        }
    }

    private func hideSidebar() {
        guard let sidebarVC = sidebarViewController else { return }
        
        UIView.animate(withDuration: 0.3, animations: {
            sidebarVC.view.frame.origin.x = -self.sidebarWidth
        }) { _ in
            sidebarVC.view.removeFromSuperview()
            sidebarVC.removeFromParent()
            self.sidebarViewController = nil
        }
    }
}

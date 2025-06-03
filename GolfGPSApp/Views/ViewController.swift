//
//  ViewController.swift
//  GolfGPSApp
//
//  Created by Samuel Goergen on 6/1/25.
//

import UIKit
import MapKit
import CoreLocation
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth
import SwiftUI

class ViewController: UIViewController, CLLocationManagerDelegate, MKMapViewDelegate, UIPickerViewDelegate, UIPickerViewDataSource {
    
// Outlets
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var pickerView: UIPickerView!
    @IBOutlet weak var distanceLabel: UILabel!
    @IBOutlet weak var recommendationLabel: UILabel!
    @IBOutlet weak var handicapLabel: UILabel!
    @IBOutlet weak var scoreTextField: UITextField!

    private var sidebarViewController: SidebarViewController?
    private var isSidebarVisible = false
    private let sidebarWidth: CGFloat = 250
    private var shouldSkipAuthCheck = false // New flag
// Actions
    @IBAction func startShot(_ sender: UIButton) {
        guard let location = locationManager.location else { return }
        startLocation = location
        distanceLabel.text = "Distance: Shot started"
        // Revert to hole distance after a brief delay
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
        // Refresh user status before saving
        userStatusViewModel.fetchUserStatus()
        saveShots()
        // Show shot distance briefly
        distanceLabel.text = String(format: "Distance: %.1f yards", distance * 1.09361)
        // Revert to hole distance after a brief delay
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
        let distance = currentLocation.distance(from: holeLocation) * 1.09361 // Yards
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
    var holeCoordinate = CLLocationCoordinate2D(latitude: 45.099087, longitude: -93.518656) // Mock hole
    let items = ["Driver", "3-Wood", "5-Wood", "7-Wood", "1-Iron", "2-Iron", "3-Iron", "4-Iron", "5-Iron", "6-Iron", "7-Iron", "8-Iron", "9-Iron", "Pitching Wedge", "Gap Wedge", "Sand Wedge", "Lob Wedge"]
    let userStatusViewModel = UserStatusViewModel()
    var startLocation: CLLocation?
    var shots: [Shot] = []
    var scores: [ScoreEntry] = []
    
    struct Shot: Codable {
        let club: String
        let distance: Double // Meters
        var id: String? // Firestore document ID
        
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
        print("DistanceLabel set")
        recommendationLabel.text = "Recommendation: None"
        print("RecommendationLabel set")
        handicapLabel.text = "Handicap: Not calculated"
        print("HandicapLabel set")
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        mapView.addGestureRecognizer(longPress)
        print("Long press gesture added")

        // Set up navigation bar with sidebar toggle
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "line.horizontal.3"), style: .plain, target: self, action: #selector(toggleSidebar))
        print("Hamburger icon set")

        // Initial distance update
        if locationManager.location != nil {
            updateDistanceToHole()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.userStatusViewModel.fetchUserStatus()
            print("After fetch: isLoggedIn = \(self.userStatusViewModel.isLoggedIn), uid = \(self.userStatusViewModel.currentUser?.uid ?? "nil")")
            if !self.userStatusViewModel.isLoggedIn {
                print("User not logged in, presenting login view")
                self.presentLoginView()
            } else if let userId = self.userStatusViewModel.currentUser?.uid {
                print("User is logged in, loading data with uid = \(userId)")
                self.loadShots()
                self.loadScores()
            } else {
                print("Inconsistent state: isLoggedIn true but no UID, presenting login view")
                self.presentLoginView()
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
            // Remove existing annotation
            let annotations = mapView.annotations
            mapView.removeAnnotations(annotations)
            // Update holeCoordinate and add new annotation
            holeCoordinate = newCoordinate
            let annotation = MKPointAnnotation()
            annotation.coordinate = holeCoordinate
            annotation.title = "Hole"
            mapView.addAnnotation(annotation)
            // Update the map region to center on the new location
            let region = MKCoordinateRegion(center: holeCoordinate, latitudinalMeters: 500, longitudinalMeters: 500)
            mapView.setRegion(region, animated: true)
            // Update distance to new pin
            updateDistanceToHole()
        }
    }
    
    func setupMapView() {
        mapView.delegate = self
        mapView.showsUserLocation = true
        // Enable user interaction for zooming and panning
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        // Add the hole annotation
        let annotation = MKPointAnnotation()
        annotation.coordinate = holeCoordinate
        annotation.title = "Hole"
        mapView.addAnnotation(annotation)
        // Set a larger initial region to allow zooming out
        let region = MKCoordinateRegion(center: holeCoordinate, latitudinalMeters: 500, longitudinalMeters: 500)
        mapView.setRegion(region, animated: true)
    }
    
    func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    // PickerView Setup
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return items.count
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return items[row]
    }
    
    private func updateDistanceToHole() {
        guard let location = locationManager.location else {
            distanceLabel.text = "Distance: Location unavailable"
            return
        }
        let holeLocation = CLLocation(latitude: holeCoordinate.latitude, longitude: holeCoordinate.longitude)
        let distance = location.distance(from: holeLocation) * 1.09361 // Convert meters to yards
        DispatchQueue.main.async {
            self.distanceLabel.text = String(format: "Distance: %.1f yards", distance)
        }
    }
    
    // Location Updates
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        updateDistanceToHole()
        let holeLocation = CLLocation(latitude: holeCoordinate.latitude, longitude: holeCoordinate.longitude)
        let distance = location.distance(from: holeLocation) * 1.09361 // Yards
        DispatchQueue.main.async {
            self.distanceLabel.text = String(format: "Distance: %.1f yards", distance)
        }        }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let alert = UIAlertController(title: "Error", message: "Location error: \(error.localizedDescription)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
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

    // Club Recommendation
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
    
    @IBAction func calculateHandicap(_ sender: UIButton) {
        guard let scoreText = scoreTextField.text, let score = Double(scoreText), let userId = userStatusViewModel.currentUser?.uid else {
            handicapLabel.text = "Handicap: Invalid score"
            print("Invalid score or no user ID")
            return
        }
        let scoreEntry = ScoreEntry(course: "Minnehaha Creek", score: score, holes: Array(1...18)) // Mock holes
        scores.append(scoreEntry)
        print("Saving score: \(score) for user: \(userId)")
        db.collection("users").document(userId).collection("Score").addDocument(data: [
            "course": scoreEntry.course,
            "score": scoreEntry.score,
            "holes": scoreEntry.holes
        ]) { error in
            if let error = error {
                print("Error saving score: \(error.localizedDescription)")
            } else {
                print("Score saved successfully")
            }
        }
        if scores.count >= 3 {
            let handicap = calculateHandicap()
            handicapLabel.text = String(format: "Handicap: %.1f", handicap)
        } else {
            handicapLabel.text = "Handicap: Need \(3 - scores.count) more scores"
        }
        scoreTextField.text = ""
    }
    
    func calculateHandicap() -> Double {
        let courseRating = 72.0 // Mock value
        let slopeRating = 113.0 // Standard
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


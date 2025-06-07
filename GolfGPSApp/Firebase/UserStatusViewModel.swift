//
//  UserStatusViewModel.swift
//  GolfGPSApp
//
//  Created by Samuel Goergen on 6/2/25.
//
import FirebaseAuth
import Combine

class UserStatusViewModel: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var currentUser: User? = nil

    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] (_, user) in
            self?.currentUser = user
            self?.isLoggedIn = user != nil
            print("Auth state changed: isLoggedIn = \(self?.isLoggedIn ?? false), uid = \(user?.uid ?? "nil")")
            // Notify subscribers only after a stable state
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }
        }
    }

    func fetchUserStatus() {
        let user = Auth.auth().currentUser
        currentUser = user
        isLoggedIn = user != nil
        print("User status fetched: isLoggedIn = \(isLoggedIn), uid = \(currentUser?.uid ?? "nil")")
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            DispatchQueue.main.async {
                self.currentUser = nil
                self.isLoggedIn = false
                print("User signed out, isLoggedIn = \(self.isLoggedIn), currentUser = \(self.currentUser?.uid ?? "nil")")
                self.objectWillChange.send()
            }
        } catch {
            print("Error signing out: \(error.localizedDescription)")
        }
    }

    deinit {
        if let handle = handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
}

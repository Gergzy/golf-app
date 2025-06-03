import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseFirestore

struct LoginView: View {
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String?
    @EnvironmentObject var userStatusViewModel: UserStatusViewModel
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Login")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom, 20)

                TextField("Email", text: $email)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal, 20)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)

                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal, 20)

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding(.horizontal, 20)
                }

                Button("Log In") {
                    authenticateUser()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding(.horizontal, 20)

                NavigationLink(destination: RegisterView()
                    .environmentObject(userStatusViewModel)) {
                        Text("Don't have an account? Register here")
                            .foregroundColor(.blue)
                            .underline()
                    }
                    .padding(.top, 10)
            }
            .padding()
        }
    }

    private func authenticateUser() {
        Auth.auth().signIn(withEmail: email, password: password) { result, error in
            if let error = error {
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                }
            } else if let user = result?.user {
                DispatchQueue.main.async {
                    let uid = user.uid
                    print("User logged in with UID: \(uid)")
                    self.userStatusViewModel.currentUser = user
                    self.userStatusViewModel.isLoggedIn = true
                    self.fetchUserDetails(uid: uid)
                    // Delay dismissal to ensure state propagates
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }

    private func fetchUserDetails(uid: String) {
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(uid)
        userRef.getDocument { document, error in
            if let document = document, document.exists {
                let userData = document.data()
                print("User data retrieved: \(String(describing: userData))")
            } else {
                print("No user data found, creating a new user entry if needed.")
                // Optionally create a new user document if needed
                userRef.setData([:]) { error in
                    if let error = error {
                        print("Error creating user document: \(error.localizedDescription)")
                    } else {
                        print("New user document created for UID: \(uid)")
                    }
                }
            }
        }
    }
}

import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseFirestore

struct RegisterView: View {
    @State private var name: String = ""
    @State private var dateOfBirth: Date = Date()
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var errorMessage: String?
    @State private var showSuccessPopup: Bool = false
    @State private var showDatePicker: Bool = false
    @EnvironmentObject var userStatusViewModel: UserStatusViewModel
    @Environment(\.presentationMode) var presentationMode

    private let maxDate = Date()

    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Create Account")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.bottom, 20)

            TextField("Full Name", text: $name)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal, 20)
                .autocapitalization(.words)

            VStack(alignment: .leading) {
                Text("Date of Birth")
                    .font(.headline)
                    .padding(.leading, 20)

                Button(action: { showDatePicker = true }) {
                    HStack {
                        Text(dateFormatter.string(from: dateOfBirth))
                            .foregroundColor(.black)
                            .padding()
                        Spacer()
                        Image(systemName: "calendar")
                            .foregroundColor(.gray)
                            .padding()
                    }
                    .background(RoundedRectangle(cornerRadius: 10).stroke(Color.gray, lineWidth: 1))
                }
                .padding(.horizontal, 20)
            }

            TextField("Email", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal, 20)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)

            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal, 20)

            SecureField("Confirm Password", text: $confirmPassword)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal, 20)

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding(.horizontal, 20)
            }

            Button("Sign Up") {
                registerUser()
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding(.horizontal, 20)
        }
        .padding()
        .alert("Account Created Successfully!", isPresented: $showSuccessPopup) {
            Button("OK") {
                presentationMode.wrappedValue.dismiss() // Dismiss modal on success
                userStatusViewModel.fetchUserStatus()
            }
        }
        .sheet(isPresented: $showDatePicker) {
            VStack {
                DatePicker("Select Your Birthday", selection: $dateOfBirth, in: ...maxDate, displayedComponents: .date)
                    .datePickerStyle(WheelDatePickerStyle())
                    .labelsHidden()
                    .padding()

                Button("Done") {
                    showDatePicker = false
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding()
        }
    }

    private func registerUser() {
        guard !name.isEmpty, !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please fill in all fields."
            return
        }

        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }

        guard dateOfBirth <= Date() else {
            errorMessage = "Invalid date of birth. Please select a valid past date."
            return
        }

        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            if let error = error {
                errorMessage = error.localizedDescription
            } else if let user = result?.user {
                saveUserInfo(uid: user.uid)
            }
        }
    }

    private func saveUserInfo(uid: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let formattedDate = dateFormatter.string(from: dateOfBirth)

        let userData: [String: Any] = [
            "name": name,
            "dateOfBirth": formattedDate,
            "email": email,
            "createdAt": Timestamp()
        ]

        Firestore.firestore().collection("users").document(uid).setData(userData) { error in
            if let error = error {
                errorMessage = "Failed to save user info: \(error.localizedDescription)"
            } else {
                showSuccessPopup = true
            }
        }
    }
}

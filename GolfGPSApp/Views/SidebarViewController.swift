import UIKit
import FirebaseAuth
import FirebaseFirestore

class SidebarViewController: UITableViewController {
    
    weak var delegate: ViewController?
    
    // Add UI elements for score input
    private let scoreTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Enter Score"
        textField.borderStyle = .roundedRect
        textField.keyboardType = .numberPad
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let handicapLabel: UILabel = {
        let label = UILabel()
        label.text = "Handicap: Not calculated"
        label.textColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let calculateButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Calculate Handicap", for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let db = Firestore.firestore()
    private var scores: [ScoreEntry] = []
    
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
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        setupAdditionalViews()
        calculateButton.addTarget(self, action: #selector(calculateHandicap), for: .touchUpInside)
    }
    
    private func setupAdditionalViews() {
        let headerView = UIView(frame: CGRect(x: 0, y: 0, width: tableView.frame.width, height: 120))
        
        headerView.addSubview(scoreTextField)
        headerView.addSubview(calculateButton)
        headerView.addSubview(handicapLabel)
        
        // Constraints
        NSLayoutConstraint.activate([
            scoreTextField.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 16),
            scoreTextField.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            scoreTextField.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            scoreTextField.heightAnchor.constraint(equalToConstant: 36),
            
            calculateButton.topAnchor.constraint(equalTo: scoreTextField.bottomAnchor, constant: 8),
            calculateButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            calculateButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            calculateButton.heightAnchor.constraint(equalToConstant: 36),
            
            handicapLabel.topAnchor.constraint(equalTo: calculateButton.bottomAnchor, constant: 8),
            handicapLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            handicapLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            handicapLabel.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        tableView.tableHeaderView = headerView
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.textLabel?.text = "Log Out"
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.row == 0 {
            print("Logout tapped in sidebar")
            delegate?.userStatusViewModel.signOut()
            print("Sign out called")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.delegate?.presentLoginView()
                print("Presenting login view after logout")
            }
            dismiss(animated: true)
        }
    }
    
    @objc func calculateHandicap() {
        guard let scoreText = scoreTextField.text, let score = Double(scoreText), let userId = Auth.auth().currentUser?.uid else {
            handicapLabel.text = "Handicap: Invalid score"
            print("Invalid score or no user ID")
            return
        }
        let scoreEntry = ScoreEntry(course: "Minnehaha Creek", score: score, holes: Array(1...18))
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
            let courseRating = 72.0
            let slopeRating = 113.0
            let differentials = scores.map { ($0.score - courseRating) * 113 / slopeRating }
            let lowest = differentials.sorted().prefix(3)
            let handicap = lowest.reduce(0, +) / Double(lowest.count) * 0.96
            handicapLabel.text = String(format: "Handicap: %.1f", handicap)
        } else {
            handicapLabel.text = "Handicap: Need \(3 - scores.count) more scores"
        }
        scoreTextField.text = ""
    }
}

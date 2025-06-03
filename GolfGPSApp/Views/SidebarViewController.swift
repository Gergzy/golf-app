//
//  SidebarViewController.swift
//  GolfGPSApp
//
//  Created by Samuel Goergen on 6/2/25.
//

import UIKit

class SidebarViewController: UITableViewController {
    
    weak var delegate: ViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
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
}

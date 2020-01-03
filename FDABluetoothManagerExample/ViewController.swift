//
//  ViewController.swift
//  FDABluetoothManagerExample
//
//  Created by Sergio Fresneda on 12/28/19.
//  Copyright © 2019 Sergio Fresneda. All rights reserved.
//

import UIKit
import CoreBluetooth

class ViewController: UIViewController {

    private var btManager: FDABluetoothManager!
    private lazy var btDevices: [CBPeripheral] = []
    private lazy var refreshControl: UIRefreshControl = UIRefreshControl()
    
    @IBOutlet weak var devicesTableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.btManager = FDABluetoothManager.init()
        self.setupTableView()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
     
    private func setupTableView() {
        self.refreshControl.addTarget(self, action: #selector(initBluetoothScan), for: .valueChanged)
        self.devicesTableView.addSubview(refreshControl)
        self.devicesTableView.delegate = self
        self.devicesTableView.dataSource = self
    }
    
    @objc private func initBluetoothScan() {
        guard self.btManager.centralManager.state != .poweredOn else {
            self.showErrorAlert(content: BTError.btNotReady.localizedDescription)
            return
        }
        
        self.btManager.scanDevices(success: { newDevice in
            guard let wrappedDevice = newDevice.getValue as? CBPeripheral else { return }
            self.btDevices.append(wrappedDevice)
            
            guard let deviceIndex = self.btDevices.firstIndex(of: wrappedDevice) else {
                self.devicesTableView.reloadData()
                return
            }
            self.devicesTableView.reloadRows(at: [IndexPath.init(row: deviceIndex, section: 0)], with: .middle)
            
        }, failure: { error in
            self.showErrorAlert(content: error.localizedDescription)
        })
    }
    
    private func showErrorAlert(content: String) {
        self.stopRefreshAnimation()
        
        let alert = UIAlertController.init(title: "Error",
                               message: content,
                               preferredStyle: .alert)
        alert.addAction(UIAlertAction.init(title: "Accept", style: .default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
    
    private func stopRefreshAnimation() {
        self.refreshControl.endRefreshing()
        self.devicesTableView.setContentOffset(.zero, animated: true)
    }
}

extension ViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return btDevices.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "cell") else { return UITableViewCell() }
        
        let btDevice = self.btDevices[indexPath.row]
        cell.textLabel?.text = btDevice.name ?? "-"
        cell.detailTextLabel?.text = btDevice.identifier.uuidString
        
        return cell
    }
}

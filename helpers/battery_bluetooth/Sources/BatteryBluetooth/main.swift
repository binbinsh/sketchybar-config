import Foundation
import CoreBluetooth
import IOKit
import IOBluetooth

// MARK: - Device Model
struct Device: Codable {
    var id: String
    var name: String
    var type: String
    var model: String?
    var level: Int
    var charging: Bool
    var parentName: String?

    init(id: String, name: String, type: String, model: String? = nil, level: Int, charging: Bool = false, parentName: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.model = model
        self.level = level
        self.charging = charging
        self.parentName = parentName
    }
}

// MARK: - Global State
var devices: [String: Device] = [:]
var scanComplete = false
let twsMergeThreshold = 5  // Merge L/R if difference < 5%

// MARK: - AirPods/Beats Model Detection (Complete Database)
// Model code format: data[6] + data[5] = "20xx" where xx is the device ID
func getHeadphoneModel(_ modelCode: String) -> String {
    switch modelCode.lowercased() {
    // AirPods
    case "2002": return "Airpods"
    case "200f": return "Airpods 2"
    case "2013": return "Airpods 3"
    case "2019", "201b": return "Airpods 4"  // 2019=no ANC, 201B=ANC
    case "200e": return "Airpods Pro"
    case "2014", "2024": return "Airpods Pro 2"  // 2014=Lightning, 2024=USB-C
    case "200a", "201f": return "Airpods Max"  // 200a=Lightning, 201f=USB-C
    // PowerBeats
    case "2003": return "PowerBeats 3"
    case "200d": return "PowerBeats 4"
    case "200b": return "PowerBeats Pro"
    // Beats Solo/Studio
    case "200c": return "Beats Solo Pro"
    case "2006": return "Beats Solo 3"
    case "2009": return "Beats Studio 3"
    case "2017": return "Beats Studio Pro"
    // Beats Buds
    case "2011": return "Beats Studio Buds"
    case "2016": return "Beats Studio Buds+"
    case "2012": return "Beats Fit Pro"
    // Beats Other
    case "2005": return "BeatsX"
    case "2010": return "Beats Flex"
    default: return "Headphones"
    }
}

// Check if model is headphone-style (no case, no separate L/R)
// Note: Beats Studio 3 is NOT headphone-style (it has a case)
func isHeadphoneStyle(_ model: String) -> Bool {
    return ["Airpods Max", "Beats Solo Pro", "Beats Solo 3", "Beats Studio Pro"].contains(model)
}

// MARK: - BLE Scanner with GATT Support
class BLEScanner: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    private var scanDuration: TimeInterval = 3.0
    private var connectedPeripherals: Set<CBPeripheral> = []
    private var peripheralLevels: [String: Int] = [:]

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            DispatchQueue.main.asyncAfter(deadline: .now() + scanDuration) {
                central.stopScan()
                // Disconnect all peripherals
                for peripheral in self.connectedPeripherals {
                    central.cancelPeripheralConnection(peripheral)
                }
                scanComplete = true
            }
        } else {
            scanComplete = true
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, !name.isEmpty else { return }
        guard let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else {
            // Non-Apple BLE device - try to connect for battery service
            if !connectedPeripherals.contains(peripheral) {
                connectedPeripherals.insert(peripheral)
                peripheral.delegate = self
                central.connect(peripheral, options: nil)
            }
            return
        }

        // Apple device (manufacturer ID 0x4C)
        guard mfgData.count > 0 && mfgData[0] == 0x4C else { return }

        // AirPods open lid message (29 bytes, type 0x07)
        if mfgData.count == 29 && mfgData[2] == 0x07 {
            parseAirPodsOpen(name: name, id: peripheral.identifier.uuidString, data: mfgData)
        }
        // AirPods closed lid message (25 bytes, type 0x12)
        else if mfgData.count == 25 && mfgData[2] == 0x12 {
            parseAirPodsClosed(name: name, id: peripheral.identifier.uuidString, data: mfgData)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([CBUUID(string: "180F")])  // Battery Service
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            if service.uuid == CBUUID(string: "180F") {
                peripheral.discoverCharacteristics([CBUUID(string: "2A19")], for: service)  // Battery Level
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == CBUUID(string: "2A19") {
                peripheral.readValue(for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == CBUUID(string: "2A19"),
           let data = characteristic.value,
           let name = peripheral.name {
            let level = Int(data[0])
            if level > 0 && level <= 100 {
                let id = peripheral.identifier.uuidString
                // Check if level increased (charging)
                let previousLevel = peripheralLevels[id]
                let charging = previousLevel != nil && level > previousLevel!
                peripheralLevels[id] = level

                devices[id] = Device(
                    id: id,
                    name: name,
                    type: "ble_device",
                    level: level,
                    charging: charging
                )
            }
        }
    }

    private func parseAirPodsOpen(name: String, id: String, data: Data) {
        let modelCode = String(format: "%02x%02x", data[6], data[5])
        let model = getHeadphoneModel(modelCode)
        let flipBit = (data[7] & 0x02) == 0

        var caseLevel = data[16]
        var leftLevel = flipBit ? data[15] : data[14]
        var rightLevel = flipBit ? data[14] : data[15]

        // Handle headphone-style devices (no case, no L/R split)
        if isHeadphoneStyle(model) {
            // Beats Studio Pro only uses rightLevel
            if model == "Beats Studio Pro" {
                if rightLevel != 255 {
                    let charging = rightLevel > 100
                    let level = (rightLevel ^ 128) & rightLevel
                    if level <= 100 {
                        devices[id] = Device(id: id, name: name, type: "ap_case", model: model, level: Int(level), charging: charging)
                    }
                }
            } else {
                // Other headphone-style: use max of left/right
                let lv = leftLevel != 255 ? leftLevel : 0
                let rv = rightLevel != 255 ? rightLevel : 0
                let charging = (leftLevel > 100 || rightLevel > 100)
                let mainLevel = max(lv, rv)
                let level = (mainLevel ^ 128) & mainLevel
                if level <= 100 {
                    devices[id] = Device(id: id, name: name, type: "ap_case", model: model, level: Int(max(Int(level), 0)), charging: charging)
                }
            }
            return
        }

        let caseName = "\(name) (Case)"

        // Case
        if caseLevel != 255 {
            let charging = caseLevel > 100
            caseLevel = (caseLevel ^ 128) & caseLevel
            if caseLevel <= 100 {
                devices["\(id)_case"] = Device(id: "\(id)_case", name: caseName, type: "ap_case", model: model, level: Int(caseLevel), charging: charging)
            }
        }

        // Left and Right - check for TWS merge
        var leftOK = false, rightOK = false
        var leftVal: Int = 0, rightVal: Int = 0
        var leftCharging = false, rightCharging = false

        if leftLevel != 255 {
            leftCharging = leftLevel > 100
            leftLevel = (leftLevel ^ 128) & leftLevel
            if leftLevel <= 100 {
                leftOK = true
                leftVal = Int(leftLevel)
            }
        }

        if rightLevel != 255 {
            rightCharging = rightLevel > 100
            rightLevel = (rightLevel ^ 128) & rightLevel
            if rightLevel <= 100 {
                rightOK = true
                rightVal = Int(rightLevel)
            }
        }

        // TWS Merge: if both available, difference < threshold, and same charging state
        if leftOK && rightOK && abs(leftVal - rightVal) < twsMergeThreshold && leftCharging == rightCharging {
            devices["\(id)_all"] = Device(
                id: "\(id)_all",
                name: "\(name) L&R",
                type: "ap_pod_all",
                model: model,
                level: min(leftVal, rightVal),
                charging: leftCharging,
                parentName: caseName
            )
        } else {
            // Show separately
            if leftOK {
                devices["\(id)_left"] = Device(id: "\(id)_left", name: "\(name) L", type: "ap_pod_left", model: model, level: leftVal, charging: leftCharging, parentName: caseName)
            }
            if rightOK {
                devices["\(id)_right"] = Device(id: "\(id)_right", name: "\(name) R", type: "ap_pod_right", model: model, level: rightVal, charging: rightCharging, parentName: caseName)
            }
        }
    }

    private func parseAirPodsClosed(name: String, id: String, data: Data) {
        let model = "Airpods Pro 2"  // Closed message is typically from Pro 2

        var caseLevel = data[12]
        var leftLevel = data[13]
        var rightLevel = data[14]

        let caseName = "\(name) (Case)"

        // Case
        if caseLevel != 255 {
            let charging = caseLevel > 100
            caseLevel = (caseLevel ^ 128) & caseLevel
            if caseLevel <= 100 {
                devices["\(id)_case"] = Device(id: "\(id)_case", name: caseName, type: "ap_case", model: model, level: Int(caseLevel), charging: charging)
            }
        }

        // Left and Right - check for TWS merge
        var leftOK = false, rightOK = false
        var leftVal: Int = 0, rightVal: Int = 0
        var leftCharging = false, rightCharging = false

        if leftLevel != 255 {
            leftCharging = leftLevel > 100
            leftLevel = (leftLevel ^ 128) & leftLevel
            if leftLevel <= 100 {
                leftOK = true
                leftVal = Int(leftLevel)
            }
        }

        if rightLevel != 255 {
            rightCharging = rightLevel > 100
            rightLevel = (rightLevel ^ 128) & rightLevel
            if rightLevel <= 100 {
                rightOK = true
                rightVal = Int(rightLevel)
            }
        }

        // TWS Merge
        if leftOK && rightOK && abs(leftVal - rightVal) < twsMergeThreshold && leftCharging == rightCharging {
            devices["\(id)_all"] = Device(
                id: "\(id)_all",
                name: "\(name) L&R",
                type: "ap_pod_all",
                model: model,
                level: min(leftVal, rightVal),
                charging: leftCharging,
                parentName: caseName
            )
        } else {
            if leftOK {
                devices["\(id)_left"] = Device(id: "\(id)_left", name: "\(name) L", type: "ap_pod_left", model: model, level: leftVal, charging: leftCharging, parentName: caseName)
            }
            if rightOK {
                devices["\(id)_right"] = Device(id: "\(id)_right", name: "\(name) R", type: "ap_pod_right", model: model, level: rightVal, charging: rightCharging, parentName: caseName)
            }
        }
    }
}

// MARK: - Magic Device Scanner (IOKit)
func scanMagicDevices() {
    let serviceTypes = [
        "AppleDeviceManagementHIDEventService",
        "AppleBluetoothHIDKeyboard",
        "BNBTrackpadDevice",
        "BNBMouseDevice"
    ]

    for serviceType in serviceTypes {
        var iterator: io_iterator_t = 0
        let matchingDict = IOServiceMatching(serviceType)

        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == KERN_SUCCESS else {
            continue
        }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let batteryPercent = IORegistryEntryCreateCFProperty(service, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int else {
                continue
            }

            guard batteryPercent > 0 && batteryPercent <= 100 else { continue }

            let productName = IORegistryEntryCreateCFProperty(service, "Product" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String ?? "Unknown Device"

            if productName.contains("Internal") { continue }

            var deviceAddress = IORegistryEntryCreateCFProperty(service, "DeviceAddress" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String ?? productName
            deviceAddress = deviceAddress.replacingOccurrences(of: "-", with: ":").uppercased()

            // Charging status: 0 = unknown, 4 = not charging, other non-zero = charging
            let statusFlags = IORegistryEntryCreateCFProperty(service, "BatteryStatusFlags" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int ?? 0
            let isCharging = statusFlags != 0 && statusFlags != 4

            var deviceType = "hid"
            let nameLower = productName.lowercased()
            if nameLower.contains("keyboard") { deviceType = "Keyboard" }
            else if nameLower.contains("trackpad") { deviceType = "Trackpad" }
            else if nameLower.contains("mouse") { deviceType = "MMouse" }

            devices[deviceAddress] = Device(id: deviceAddress, name: productName, type: deviceType, level: batteryPercent, charging: isCharging)
        }

        IOObjectRelease(iterator)
    }
}

// MARK: - IOBluetooth Device Scanner (for paired devices)
func scanIOBluetoothDevices() {
    guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }

    for device in pairedDevices {
        guard device.isConnected() else { continue }
        guard let name = device.name, !name.isEmpty else { continue }
        guard let address = device.addressString else { continue }

        let mac = address.uppercased().replacingOccurrences(of: "-", with: ":")

        // Skip if already detected
        if devices[mac] != nil { continue }

        // Skip Apple devices (handled by BLE scanner)
        let isAppleSelector = NSSelectorFromString("isAppleDevice")
        if device.responds(to: isAppleSelector) {
            if let result = device.perform(isAppleSelector) {
                let isApple = Int(bitPattern: result.toOpaque()) != 0
                if isApple { continue }
            }
        }

        // Try to get battery level using private API
        let selector = NSSelectorFromString("batteryPercentSingle")
        if device.responds(to: selector) {
            let level = device.perform(selector)?.toOpaque()
            if let levelPtr = level {
                let batteryLevel = Int(bitPattern: levelPtr)
                if batteryLevel > 0 && batteryLevel <= 100 {
                    var deviceType = "hid"
                    let nameLower = name.lowercased()
                    if nameLower.contains("keyboard") { deviceType = "Keyboard" }
                    else if nameLower.contains("trackpad") { deviceType = "Trackpad" }
                    else if nameLower.contains("mouse") { deviceType = "MMouse" }
                    else if nameLower.contains("headphone") || nameLower.contains("headset") { deviceType = "Headphones" }

                    devices[mac] = Device(id: mac, name: name, type: deviceType, level: batteryLevel, charging: false)
                }
            }
        }
    }
}

// MARK: - System Profiler Scanner
func scanSystemProfiler() {
    let task = Process()
    task.launchPath = "/usr/sbin/system_profiler"
    task.arguments = ["SPBluetoothDataType", "-json"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()

    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        return
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let btData = json["SPBluetoothDataType"] as? [[String: Any]],
          let btInfo = btData.first else {
        return
    }

    // Check both connected and not_connected devices
    let allDevices = (btInfo["device_connected"] as? [[String: Any]] ?? []) +
                     (btInfo["device_not_connected"] as? [[String: Any]] ?? [])

    for deviceWrapper in allDevices {
        for (deviceName, deviceInfo) in deviceWrapper {
            guard let info = deviceInfo as? [String: Any] else { continue }

            let address = info["device_address"] as? String ?? deviceName
            let minorType = (info["device_minorType"] as? String ?? "device").lowercased()

            // Skip if already have this device
            if devices[address] != nil { continue }

            var deviceType = "hid"
            if minorType.contains("keyboard") { deviceType = "Keyboard" }
            else if minorType.contains("trackpad") { deviceType = "Trackpad" }
            else if minorType.contains("mouse") { deviceType = "MMouse" }
            else if minorType.contains("headphone") || minorType.contains("headset") { deviceType = "Headphones" }

            // Main battery level - skip Apple devices (they are handled by BLE/IOKit)
            if let mainLevel = info["device_batteryLevelMain"] as? String {
                let vendorID = info["device_vendorID"] as? String ?? ""
                if vendorID != "0x004C" {  // Skip Apple devices
                    let cleaned = mainLevel.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
                    if let level = Int(cleaned), level > 0, level <= 100 {
                        devices[address] = Device(id: address, name: deviceName, type: deviceType, level: level, charging: false)
                    }
                }
            }

            // AirPods from system_profiler cache - only if BLE didn't detect
            let hasAirPodsFromBLE = devices.values.contains { $0.type.hasPrefix("ap_") && $0.name.hasPrefix(deviceName.components(separatedBy: "'").first ?? deviceName) }
            if !hasAirPodsFromBLE {
                let caseName = "\(deviceName) (Case)"

                var caseLevel: Int? = nil
                var leftLevel: Int? = nil
                var rightLevel: Int? = nil

                if let level = info["device_batteryLevelCase"] as? String {
                    let cleaned = level.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
                    caseLevel = Int(cleaned)
                }
                if let level = info["device_batteryLevelLeft"] as? String {
                    let cleaned = level.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
                    leftLevel = Int(cleaned)
                }
                if let level = info["device_batteryLevelRight"] as? String {
                    let cleaned = level.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
                    rightLevel = Int(cleaned)
                }

                if let cl = caseLevel, cl > 0, cl <= 100 {
                    devices["\(address)_case"] = Device(id: "\(address)_case", name: caseName, type: "ap_case", level: cl, charging: false)
                }

                // TWS Merge for system_profiler data
                if let ll = leftLevel, let rl = rightLevel, ll > 0, ll <= 100, rl > 0, rl <= 100 {
                    if abs(ll - rl) < twsMergeThreshold {
                        devices["\(address)_all"] = Device(id: "\(address)_all", name: "\(deviceName) L&R", type: "ap_pod_all", level: min(ll, rl), charging: false, parentName: caseName)
                    } else {
                        devices["\(address)_left"] = Device(id: "\(address)_left", name: "\(deviceName) L", type: "ap_pod_left", level: ll, charging: false, parentName: caseName)
                        devices["\(address)_right"] = Device(id: "\(address)_right", name: "\(deviceName) R", type: "ap_pod_right", level: rl, charging: false, parentName: caseName)
                    }
                } else {
                    if let ll = leftLevel, ll > 0, ll <= 100 {
                        devices["\(address)_left"] = Device(id: "\(address)_left", name: "\(deviceName) L", type: "ap_pod_left", level: ll, charging: false, parentName: caseName)
                    }
                    if let rl = rightLevel, rl > 0, rl <= 100 {
                        devices["\(address)_right"] = Device(id: "\(address)_right", name: "\(deviceName) R", type: "ap_pod_right", level: rl, charging: false, parentName: caseName)
                    }
                }
            }
        }
    }
}

// MARK: - Log Reader for HID Devices (Logitech, etc.)
func scanLogReader() {
    let task = Process()
    task.launchPath = "/usr/bin/log"
    task.arguments = ["show", "--style", "compact", "--level", "info",
                      "--predicate", "subsystem == \"com.apple.bluetooth\" AND category == \"CBStackDeviceMonitor\" AND eventMessage CONTAINS \"Battery\"",
                      "--last", "30m"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()

    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        return
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return }

    var latestByMac: [String: (name: String, type: String, level: Int, charging: Bool)] = [:]

    for line in output.split(separator: "\n") {
        // Skip Apple devices
        if line.contains("VID 0x004C") { continue }

        let lineStr = String(line)

        // Extract fields
        guard let nameMatch = lineStr.range(of: ", Nm '([^']*)'", options: .regularExpression),
              let battMatch = lineStr.range(of: ", Battery M ([+-]?\\d+)%", options: .regularExpression),
              let macMatch = lineStr.range(of: ", BDA ([A-Fa-f0-9:]+)", options: .regularExpression) else {
            continue
        }

        let nameRange = lineStr[nameMatch]
        let name = String(nameRange.dropFirst(6).dropLast(1))

        let battRange = lineStr[battMatch]
        let battStr = battRange.dropFirst(12).dropLast(1)
        let charging = battStr.hasPrefix("+")
        guard let level = Int(battStr.filter { $0.isNumber }) else { continue }

        let macRange = lineStr[macMatch]
        let mac = String(macRange.dropFirst(6))

        var deviceType = "device"
        if let typeMatch = lineStr.range(of: ", DvT ([A-Za-z]+)", options: .regularExpression) {
            let typeStr = String(lineStr[typeMatch].dropFirst(6)).lowercased()
            if typeStr.contains("mouse") { deviceType = "mouse" }
            else if typeStr.contains("keyboard") { deviceType = "keyboard" }
            else if typeStr.contains("trackpad") { deviceType = "trackpad" }
        }

        latestByMac[mac] = (name: name, type: deviceType, level: level, charging: charging)
    }

    for (mac, info) in latestByMac {
        if devices[mac] == nil {
            devices[mac] = Device(id: mac, name: info.name, type: info.type, level: info.level, charging: info.charging)
        }
    }
}

// MARK: - iOS Device Scanner (with Apple Watch support)
func scanIOSDevices() {
    var ideviceIdPath: String?
    for path in ["/opt/homebrew/bin/idevice_id", "/usr/local/bin/idevice_id"] {
        if FileManager.default.isExecutableFile(atPath: path) {
            ideviceIdPath = path
            break
        }
    }

    guard let idPath = ideviceIdPath else { return }

    let infoPath = idPath.replacingOccurrences(of: "idevice_id", with: "ideviceinfo")
    guard FileManager.default.isExecutableFile(atPath: infoPath) else { return }

    func runCmd(_ path: String, _ args: [String], timeout: Int = 5) -> String? {
        let task = Process()
        task.launchPath = path
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()

            // Add timeout
            let deadline = DispatchTime.now() + .seconds(timeout)
            DispatchQueue.global().asyncAfter(deadline: deadline) {
                if task.isRunning { task.terminate() }
            }

            task.waitUntilExit()
        } catch { return nil }

        guard task.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }

    var deviceIDs: [(String, String)] = []

    // USB devices
    if let usbOutput = runCmd(idPath, ["-l"]) {
        for line in usbOutput.split(separator: "\n") {
            let id = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty { deviceIDs.append((id, "-l")) }
        }
    }

    // Network devices
    if let netOutput = runCmd(idPath, ["-n"]) {
        for line in netOutput.split(separator: "\n") {
            let id = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty && !deviceIDs.contains(where: { $0.0 == id }) {
                deviceIDs.append((id, "-n"))
            }
        }
    }

    for (deviceID, connType) in deviceIDs {
        guard let info = runCmd(infoPath, [connType, "-u", deviceID]) else { continue }

        var deviceName: String?
        var deviceClass: String?
        var productType: String?

        for line in info.split(separator: "\n") {
            let l = String(line)
            if l.hasPrefix("DeviceName:") { deviceName = l.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespaces) }
            else if l.hasPrefix("DeviceClass:") { deviceClass = l.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespaces) }
            else if l.hasPrefix("ProductType:") { productType = l.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespaces) }
        }

        guard let name = deviceName else { continue }

        // Get battery info
        guard let batteryInfo = runCmd(infoPath, [connType, "-u", deviceID, "-q", "com.apple.mobile.battery"]) else { continue }

        var batteryLevel: Int?
        var isCharging = false

        for line in batteryInfo.split(separator: "\n") {
            let l = String(line)
            if l.hasPrefix("BatteryCurrentCapacity:") {
                batteryLevel = Int(l.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespaces) ?? "")
            } else if l.hasPrefix("BatteryIsCharging:") {
                isCharging = l.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespaces) == "true"
            }
        }

        if let level = batteryLevel, level >= 0, level <= 100 {
            let deviceType = deviceClass?.lowercased() ?? "iphone"
            devices[deviceID] = Device(id: deviceID, name: name, type: deviceType, model: productType, level: level, charging: isCharging)

            // Try to detect Apple Watch paired with this device
            scanAppleWatch(iPhoneID: deviceID, iPhoneName: name, connType: connType, infoPath: infoPath)
        }
    }
}

// MARK: - Apple Watch Scanner (via iPhone)
func scanAppleWatch(iPhoneID: String, iPhoneName: String, connType: String, infoPath: String) {
    // Look for comptest tool (companion test for watch)
    var comptestPath: String?
    for path in ["/opt/homebrew/bin/comptest", "/usr/local/bin/comptest"] {
        if FileManager.default.isExecutableFile(atPath: path) {
            comptestPath = path
            break
        }
    }

    guard let compPath = comptestPath else { return }

    let task = Process()
    task.launchPath = compPath
    task.arguments = [iPhoneID]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()

    do {
        try task.run()

        let deadline = DispatchTime.now() + .seconds(10)
        DispatchQueue.global().asyncAfter(deadline: deadline) {
            if task.isRunning { task.terminate() }
        }

        task.waitUntilExit()
    } catch { return }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return }

    var watchID: String?
    var watchName: String?
    var watchModel: String?
    var watchLevel: Int?
    var watchCharging = false

    for line in output.split(separator: "\n") {
        let l = String(line)
        if l.contains("Checking watch") {
            watchID = l.components(separatedBy: " ").last
        } else if l.hasPrefix("DeviceName:") {
            watchName = l.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespaces)
        } else if l.hasPrefix("ProductType:") {
            watchModel = l.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespaces)
        } else if l.hasPrefix("BatteryCurrentCapacity:") {
            watchLevel = Int(l.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespaces) ?? "")
        } else if l.hasPrefix("BatteryIsCharging:") {
            watchCharging = l.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespaces) == "true"
        }
    }

    if let id = watchID, let name = watchName, let level = watchLevel, level >= 0, level <= 100 {
        devices[id] = Device(id: id, name: name, type: "watch", model: watchModel, level: level, charging: watchCharging, parentName: iPhoneName)
    }
}

// MARK: - Main
// Start BLE scan first (highest priority for AirPods)
let bleScanner = BLEScanner()

// Wait for BLE scan to complete
while !scanComplete {
    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
}

// Scan Magic devices
scanMagicDevices()

// Scan IOBluetooth paired devices
scanIOBluetoothDevices()

// Scan system profiler (will skip AirPods if BLE already found them)
scanSystemProfiler()

// Scan log reader for HID devices
scanLogReader()

// Scan iOS devices (including Apple Watch)
scanIOSDevices()

// Output JSON - sort by name, group by parent
var deviceList = Array(devices.values)

// Sort: devices without parent first, then by name
deviceList.sort { d1, d2 in
    if d1.parentName == nil && d2.parentName != nil { return true }
    if d1.parentName != nil && d2.parentName == nil { return false }
    return d1.name < d2.name
}

if let jsonData = try? JSONEncoder().encode(deviceList) {
    FileHandle.standardOutput.write(jsonData)
}

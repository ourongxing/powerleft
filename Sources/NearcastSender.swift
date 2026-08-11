import AppKit
import CryptoKit
import Foundation
import MultipeerConnectivity

private struct AirBatteryDevice: Encodable {
    let hasBattery: Bool
    let deviceID: String
    let deviceType: String
    let deviceName: String
    let deviceModel: String
    let batteryLevel: Int
    let isCharging: Int
    let isCharged = false
    let isPaused = false
    let acPowered = false
    let isHidden = false
    let lowPower = false
    let parentName = ""
    let lastUpdate: Double
    let realUpdate = 0.0
}

private struct NearcastMessage: Encodable {
    let id: String
    let sender: String
    let command: String
    let content: String
}

private struct MultipeerEnvelope: Encodable {
    let type = "Data"
    let payload: Data
}

final class NearcastSender: NSObject, MCNearbyServiceBrowserDelegate, MCNearbyServiceAdvertiserDelegate, MCSessionDelegate {
    private let device: DeviceDescriptor
    private let groupID: String
    private let peer: MCPeerID
    private lazy var session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .none)
    private lazy var browser = MCNearbyServiceBrowser(peer: peer, serviceType: "airbattery-nc")
    private lazy var advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: nil, serviceType: "airbattery-nc")
    private let requestRefresh: () -> Void
    private var latestReading: BatteryReading?
    private var lastSentReading: BatteryReading?

    init?(device: DeviceDescriptor, groupID: String, requestRefresh: @escaping () -> Void) {
        guard groupID.hasPrefix("nc-"), groupID.count >= 23 else { return nil }
        self.device = device
        self.groupID = groupID
        self.peer = MCPeerID(displayName: device.name)
        self.requestRefresh = requestRefresh
        super.init()
        session.delegate = self
        browser.delegate = self
        advertiser.delegate = self
    }

    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func update(_ reading: BatteryReading) {
        latestReading = reading
        _ = send(reading: reading, hasBattery: true, refresh: lastSentReading != reading)
    }

    @discardableResult
    func sendOffline() -> Bool {
        guard let reading = latestReading ?? lastSentReading else { return false }
        return send(reading: reading, hasBattery: false, refresh: false)
    }

    private func send(reading: BatteryReading, hasBattery: Bool, refresh: Bool) -> Bool {
        guard !session.connectedPeers.isEmpty else { return false }
        do {
            let airBatteryDevice = AirBatteryDevice(
                hasBattery: hasBattery,
                deviceID: device.identifier,
                deviceType: device.category,
                deviceName: device.name,
                deviceModel: device.name,
                batteryLevel: reading.percent,
                isCharging: reading.isCharging ? 1 : 0,
                lastUpdate: Date().timeIntervalSince1970
            )
            let devices = try JSONEncoder().encode([airBatteryDevice])
            guard let json = String(data: devices, encoding: .utf8) else { return false }
            let key = Self.key(for: groupID)
            let sealed = try AES.GCM.seal(Data(json.utf8), using: key)
            guard let encrypted = sealed.combined?.base64EncodedString() else { return false }
            let message = NearcastMessage(
                id: String(groupID.prefix(15)),
                sender: device.identifier,
                command: "",
                content: encrypted
            )
            let payload = try JSONEncoder().encode(message)
            let envelope = try JSONEncoder().encode(MultipeerEnvelope(payload: payload))
            try session.send(envelope, toPeers: session.connectedPeers, with: .reliable)
            if hasBattery { lastSentReading = reading }
            if refresh { requestRefresh() }
            return true
        } catch {
            NSLog("Nearcast 发送失败：\(error)")
            return false
        }
    }

    private static func key(for groupID: String) -> SymmetricKey {
        let password = String(groupID.dropFirst(15).prefix(8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(password.utf8)),
            salt: Data(groupID.prefix(15).utf8),
            info: Data(),
            outputByteCount: 32
        )
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) { NSLog("Nearcast 浏览失败：\(error)") }
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) { NSLog("Nearcast 广播失败：\(error)") }

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        invitationHandler(true, session)
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        guard state == .connected else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let reading = self.latestReading else { return }
            _ = self.send(reading: reading, hasBattery: true, refresh: true)
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

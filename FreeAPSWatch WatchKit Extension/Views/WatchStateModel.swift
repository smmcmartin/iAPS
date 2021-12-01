import Combine
import Foundation
import SwiftUI
import WatchConnectivity

class WatchStateModel: NSObject, ObservableObject {
    var session: WCSession

    @Published var glucose = "00"
    @Published var trend = "→"
    @Published var delta = "+00"
    @Published var lastLoopDate: Date?
    @Published var glucoseDate: Date?
    @Published var bolusIncrement: Decimal?
    @Published var maxCOB: Decimal?
    @Published var maxBolus: Decimal?
    @Published var bolusRecommended: Decimal?
    @Published var carbsRequired: Decimal?
    @Published var iob: Decimal?
    @Published var cob: Decimal?
    @Published var tempTargets: [TempTargetWatchPreset] = []
    @Published var bolusAfterCarbs = true

    @Published var isCarbsViewActive = false
    @Published var isTempTargetViewActive = false
    @Published var isBolusViewActive = false
    @Published var isConfirmationViewActive = false
    @Published var confirmationSuccess: Bool?

    private var lifetime = Set<AnyCancellable>()
    let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    init(session: WCSession = .default) {
        self.session = session
        super.init()

        session.delegate = self
        session.activate()
    }

    func addCarbs(_ carbs: Int) {
        confirmationSuccess = nil
        isConfirmationViewActive = true
        isCarbsViewActive = false
        session.sendMessage(["carbs": carbs], replyHandler: { reply in
            self.completionHandler(reply)
            if let ok = reply["confirmation"] as? Bool, ok, self.bolusAfterCarbs {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.isBolusViewActive = true
                }
            }
        }) { error in
            print(error.localizedDescription)
            DispatchQueue.main.async {
                self.confirmation(false)
            }
        }
    }

    func enactTempTarget(id: String) {
        confirmationSuccess = nil
        isConfirmationViewActive = true
        isTempTargetViewActive = false
        session.sendMessage(["tempTarget": id], replyHandler: completionHandler) { error in
            print(error.localizedDescription)
            DispatchQueue.main.async {
                self.confirmation(false)
            }
        }
    }

    func enactBolus(amount: Double) {
        confirmationSuccess = nil
        isConfirmationViewActive = true
        isBolusViewActive = false
        session.sendMessage(["bolus": amount], replyHandler: completionHandler) { error in
            print(error.localizedDescription)
            DispatchQueue.main.async {
                self.confirmation(false)
            }
        }
    }

    func requestState() {
        guard session.activationState == .activated else {
            session.activate()
            return
        }
        session.sendMessage(["stateRequest": true], replyHandler: nil) { error in
            print("WatchStateModel error: " + error.localizedDescription)
        }
    }

    private func completionHandler(_ reply: [String: Any]) {
        if let ok = reply["confirmation"] as? Bool {
            DispatchQueue.main.async {
                self.confirmation(ok)
            }
        } else {
            DispatchQueue.main.async {
                self.confirmation(false)
            }
        }
    }

    private func confirmation(_ ok: Bool) {
        WKInterfaceDevice.current().play(ok ? .success : .failure)
        withAnimation {
            confirmationSuccess = ok
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                self.isConfirmationViewActive = false
            }
        }
    }

    private func processState(_ state: WatchState) {
        glucose = state.glucose ?? "?"
        trend = state.trend ?? "?"
        delta = state.delta ?? "?"
        glucoseDate = state.glucoseDate
        lastLoopDate = state.lastLoopDate
        bolusIncrement = state.bolusIncrement
        maxCOB = state.maxCOB
        maxBolus = state.maxBolus
        bolusRecommended = state.bolusRecommended
        carbsRequired = state.carbsRequired
        iob = state.iob
        cob = state.cob
        tempTargets = state.tempTargets
        bolusAfterCarbs = state.bolusAfterCarbs ?? true
    }
}

extension WatchStateModel: WCSessionDelegate {
    func session(_: WCSession, activationDidCompleteWith state: WCSessionActivationState, error _: Error?) {
        print("WCSession activated: \(state == .activated)")
        requestState()
    }

    func session(_: WCSession, didReceiveMessage _: [String: Any]) {}

    func sessionReachabilityDidChange(_ session: WCSession) {
        print("WCSession Reachability: \(session.isReachable)")
    }

    func session(_: WCSession, didReceiveMessageData messageData: Data) {
        if let state = try? JSONDecoder().decode(WatchState.self, from: messageData) {
            DispatchQueue.main.async {
//                WKInterfaceDevice.current().play(.click)
                self.processState(state)
            }
        }
    }
}

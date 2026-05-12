import Foundation

public enum PaymentError: Error, Equatable, Sendable {
    case capExceeded(quotedUSD: Decimal, capUSD: Decimal)
    case noSupportedMethod(offered: [String])
    case settlementReverted(txHash: String)
    case settlementTimeout(txHash: String)
    case malformedChallenge(String)
    case insufficientFunds(needed: Decimal, haveUSDC: Decimal?, haveETH: Decimal?)
    case other(String)
}

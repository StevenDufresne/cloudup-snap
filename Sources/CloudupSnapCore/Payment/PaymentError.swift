import Foundation

public enum PaymentError: Error, Equatable, Sendable, CustomStringConvertible, LocalizedError {
    case capExceeded(quotedUSD: Decimal, capUSD: Decimal)
    case noSupportedMethod(offered: [String])
    case settlementReverted(txHash: String)
    case settlementTimeout(txHash: String)
    case malformedChallenge(String)
    case insufficientFunds(needed: Decimal, haveUSDC: Decimal?, haveETH: Decimal?)
    /// Cloudup returned an x402-style payment challenge we don't yet pay
    /// automatically. Surfaces enough info to tell the user how much to fund.
    case paymentRequired(amountUSD: Decimal, currency: String)
    case other(String)

    /// User-facing message. Avoid leaking enum syntax or technical jargon.
    public var description: String {
        switch self {
        case .capExceeded(let q, let cap):
            return "This upload would cost $\(q), which is above your $\(cap) spending cap."
        case .noSupportedMethod(let offered):
            return "Cloudup offered payment methods we can't pay (\(offered.joined(separator: ", "))). Update needed."
        case .settlementReverted(let txHash):
            return "The on-chain payment was rejected. Tx \(txHash). Wallet may be out of USDC or ETH for gas."
        case .settlementTimeout(let txHash):
            return "The on-chain payment was sent but didn't confirm in time. Tx \(txHash). It may still arrive — try again in a minute."
        case .malformedChallenge(let detail):
            return "Cloudup returned an unexpected payment challenge: \(detail)"
        case .insufficientFunds(let needed, let usdc, let eth):
            let usdcPart = usdc.map { "\($0) USDC" } ?? "?? USDC"
            let ethPart  = eth.map  { "\($0) ETH"  } ?? "?? ETH"
            return "Wallet has only \(usdcPart) and \(ethPart), but \(needed) is needed. Fund the wallet from a Base Sepolia faucet."
        case .paymentRequired(let amount, let currency):
            return "Cloudup requires a \(amount) \(currency) payment to upload. Add testnet funds to your wallet, then try again."
        case .other(let detail):
            return detail
        }
    }

    public var errorDescription: String? { description }
}

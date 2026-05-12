import Foundation

enum PaymentChallengeSamples {
    static let basicChallengeJSON = """
    {
      "challenges": [
        {
          "challenge_id": "ch_abc123",
          "sku": "upload-screenshot",
          "amount": "0.10",
          "opaque": "srv-nonce-xyz789",
          "methods": [
            {
              "id": "erc20-usdc-base-sepolia",
              "network": "base-sepolia",
              "currency": "USDC",
              "currency_contract": "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
              "currency_decimals": 6,
              "recipient_address": "0xc5F06701bd664159620F1a83A64A57ebCEF9151b"
            }
          ]
        }
      ]
    }
    """
}

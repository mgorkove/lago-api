# frozen_string_literal: true

module Types
  module PaymentProviders
    class AdyenInput < BaseInputObject
      description 'Adyen input arguments'

      argument :api_key, String, required: true
      argument :hmac_key, String, required: false
      argument :live_prefix, String, required: false
      argument :merchant_account, String, required: true
    end
  end
end

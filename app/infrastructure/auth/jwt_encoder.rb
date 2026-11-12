# frozen_string_literal: true

require "jwt"

module Auth
  class JwtEncoder
    ALGORITHM = "HS256"

    def initialize(secret: self.class.default_secret)
      raise ArgumentError, "JWT secret cannot be blank" if secret.to_s.empty?

      @secret = secret
    end

    def encode(payload)
      JWT.encode(payload, @secret, ALGORITHM)
    end

    # Returns the decoded payload hash on success, nil on any failure
    # (invalid signature, malformed token, expired token).
    def decode(token)
      payload, = JWT.decode(token, @secret, true, { algorithm: ALGORITHM })
      payload
    rescue JWT::DecodeError
      nil
    end

    def self.default_secret
      Rails.application.credentials.dig(:jwt, :secret) ||
        ENV.fetch("JWT_SECRET", nil) ||
        Rails.application.secret_key_base
    end
  end
end

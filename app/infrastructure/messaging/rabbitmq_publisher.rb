# frozen_string_literal: true

require "bunny"
require "json"

module Messaging
  # Publica eventos de domínio no exchange de tópico compartilhado pelos microsserviços.
  # A routing key é o nome do evento (ex.: "work_order.diagnosed").
  class RabbitmqPublisher
    EXCHANGE = "oficina.events"
    CONNECTION_LOCK = Mutex.new

    def self.connection
      CONNECTION_LOCK.synchronize do
        @connection = nil unless @connection&.open?
        @connection ||= Bunny.new(ENV.fetch("RABBITMQ_URL")).tap(&:start)
      end
    end

    def initialize(connection: nil)
      @connection = connection
    end

    def publish(event, data)
      # shortcut: um canal por publicação (canais do Bunny não são thread-safe);
      # usar pool de canais se o volume de eventos crescer.
      channel = (@connection || self.class.connection).create_channel
      channel.topic(EXCHANGE, durable: true).publish(
        JSON.generate(event: event, occurred_at: Time.now.utc.iso8601, data: data),
        routing_key: event, persistent: true, content_type: "application/json"
      )
    ensure
      channel&.close
    end
  end
end

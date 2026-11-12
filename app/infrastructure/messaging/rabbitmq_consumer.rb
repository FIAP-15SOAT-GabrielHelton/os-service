# frozen_string_literal: true

require "bunny"
require "json"

module Messaging
  # Consome eventos do exchange compartilhado em uma fila durável deste serviço.
  # handlers: { "routing.key" => ->(data) { ... } } — o handler levanta exceção para sinalizar falha.
  class RabbitmqConsumer
    def initialize(queue:, handlers:, connection: nil)
      @queue = queue
      @handlers = handlers
      @connection = connection
    end

    def start
      channel = (@connection || RabbitmqPublisher.connection).create_channel
      channel.prefetch(1)
      exchange = channel.topic(RabbitmqPublisher::EXCHANGE, durable: true)
      queue = channel.queue(@queue, durable: true)
      @handlers.each_key { |routing_key| queue.bind(exchange, routing_key: routing_key) }

      queue.subscribe(manual_ack: true, block: true) do |delivery, _properties, body|
        handle(channel, delivery, body)
      end
    end

    private

    def handle(channel, delivery, body)
      Rails.application.executor.wrap do
        @handlers.fetch(delivery.routing_key).call(JSON.parse(body).fetch("data"))
      end
      channel.ack(delivery.delivery_tag)
    rescue StandardError => e
      Rails.logger.error("[RabbitmqConsumer] #{delivery.routing_key} failed: #{e.message}")
      ::NewRelic::Agent.notice_error(e)
      # shortcut: uma única nova tentativa e depois descarta; adicionar dead-letter queue
      # se for preciso inspecionar ou reprocessar eventos que falharam.
      channel.reject(delivery.delivery_tag, !delivery.redelivered?)
    end
  end
end

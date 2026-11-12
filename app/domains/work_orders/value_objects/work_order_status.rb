# frozen_string_literal: true

module WorkOrders
  module ValueObjects
    class WorkOrderStatus
      STATES = %i[
        received
        diagnosing
        awaiting_approval
        approved
        in_progress
        completed
        paid
        delivered
        rejected
        cancelled
      ].freeze

      TRANSITIONS = {
        received: %i[diagnosing rejected],
        diagnosing: %i[awaiting_approval rejected],
        # cancelled: compensação da Saga (sem estoque na aprovação ou falha na execução)
        awaiting_approval: %i[approved rejected cancelled],
        approved: %i[in_progress cancelled],
        in_progress: %i[completed cancelled],
        # completed = aguardando pagamento; a entrega só é liberada pelo evento payment.approved
        completed: %i[paid],
        paid: %i[delivered],
        delivered: [],
        rejected: [],
        cancelled: []
      }.freeze

      attr_reader :value

      def initialize(value = :received)
        @value = value.to_sym
        raise ArgumentError, "Invalid status: #{value}" unless STATES.include?(@value)
      end

      def can_transition_to?(new_state)
        TRANSITIONS[@value].include?(new_state.to_sym)
      end

      def transition_to(new_state)
        new_state = new_state.to_sym
        raise "Invalid transition from #{@value} to #{new_state}" unless can_transition_to?(new_state)

        self.class.new(new_state)
      end

      def terminal?
        TRANSITIONS[@value].empty?
      end

      def ==(other)
        other.is_a?(self.class) && other.value == value
      end

      alias eql? ==

      def hash
        [ self.class, value ].hash
      end

      def to_s
        value.to_s
      end

      def to_sym
        value
      end
    end
  end
end

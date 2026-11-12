# frozen_string_literal: true

class WorkOrderMailer < ApplicationMailer
  STATUS_LABELS = {
    awaiting_approval: "Aguardando aprovação do orçamento",
    approved:          "Orçamento aprovado",
    in_progress:       "Serviço em execução",
    completed:         "Serviço concluído — veículo pronto para retirada",
    paid:              "Pagamento confirmado — veículo liberado para retirada",
    delivered:         "Veículo entregue",
    rejected:          "Orçamento recusado",
    cancelled:         "Ordem de serviço cancelada"
  }.freeze

  def status_changed(work_order, customer_email)
    @protocol    = work_order.protocol
    @status      = work_order.status.to_sym
    @status_label = STATUS_LABELS.fetch(@status, work_order.status.to_s)

    mail(
      to: customer_email,
      subject: "Ordem de Serviço #{@protocol} — #{@status_label}"
    )
  end
end

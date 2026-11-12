# language: pt
Funcionalidade: Fluxo da ordem de serviço na Saga
  Como oficina
  Quero que a ordem de serviço avance conforme os outros serviços respondem
  Para entregar o veículo só depois de executado e pago

  Contexto:
    Dado um cliente com um veículo cadastrado
    E um serviço "Troca de óleo" de 150 reais
    E uma peça "Filtro de óleo" com 3 unidades em estoque

  Cenário: Da abertura à entrega, com pagamento aprovado
    Dado uma ordem de serviço aberta com o serviço e 2 unidades da peça
    Quando o mecânico conclui o diagnóstico
    Então a ordem de serviço fica "awaiting_approval"
    E o evento "work_order.diagnosed" é publicado
    Quando o Billing informa que o orçamento foi aprovado
    Então a ordem de serviço fica "approved"
    E o estoque da peça passa a ser 1
    Quando o Execution informa que a execução começou
    E o Execution informa que a execução terminou
    Então a ordem de serviço fica "completed"
    E a entrega é recusada por falta de pagamento
    Quando o Billing informa que o pagamento foi aprovado
    Então a ordem de serviço fica "paid"
    Quando o atendente registra a entrega
    Então a ordem de serviço fica "delivered"

  Cenário: Falha na execução desfaz a aprovação
    Dado uma ordem de serviço aberta com o serviço e 2 unidades da peça
    E o mecânico conclui o diagnóstico
    E o Billing informa que o orçamento foi aprovado
    E o Execution informa que a execução começou
    Quando o Execution informa que a execução falhou
    Então a ordem de serviço fica "cancelled"
    E o estoque da peça passa a ser 3
    E o evento "work_order.cancelled" é publicado

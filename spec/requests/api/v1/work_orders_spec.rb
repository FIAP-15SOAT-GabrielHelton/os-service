# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::WorkOrders', openapi_spec: 'v1/swagger.json', type: :request do
  path '/api/v1/work_orders' do
    get 'List work orders' do
      tags 'Work Orders'
      produces 'application/json'
      security [ { bearerAuth: [] } ]
      parameter name: :status, in: :query, type: :string, required: false,
                description: 'Filter by status (received, diagnosing, awaiting_approval, approved, in_progress, completed, delivered, rejected)'
      parameter name: :customer_id, in: :query, type: :integer, required: false, description: 'Filter by customer ID'
      parameter name: :mechanic_id, in: :query, type: :integer, required: false, description: 'Filter by mechanic ID'
      parameter name: :page, in: :query, type: :integer, required: false, description: 'Page number'
      parameter name: :per_page, in: :query, type: :integer, required: false, description: 'Items per page'

      response '200', 'successful' do
        schema type: :object,
               properties: {
                 data: { type: :array, items: { '$ref' => '#/components/schemas/WorkOrder' } },
                 pagination: {
                   type: :object,
                   properties: {
                     page: { type: :integer },
                     per_page: { type: :integer },
                     total: { type: :integer },
                     total_pages: { type: :integer }
                   }
                 }
               }
        run_test!
      end

      response '401', 'unauthorized' do
        run_test!
      end
    end

    post 'Create work order' do
      tags 'Work Orders'
      consumes 'application/json'
      produces 'application/json'
      security [ { bearerAuth: [] } ]
      parameter name: :work_order, in: :body, schema: {
        type: :object,
        properties: {
          customer_id: { type: :integer },
          vehicle_id: { type: :integer },
          problem_description: { type: :string },
          line_items: {
            type: :array,
            description: 'Optional pre-filled items (services/parts). When present the OS starts in diagnosing status.',
            items: {
              type: :object,
              properties: {
                item_type: { type: :string, enum: %w[service part] },
                reference_id: { type: :integer },
                quantity: { type: :integer }
              },
              required: %w[item_type reference_id quantity]
            }
          }
        },
        required: %w[customer_id vehicle_id problem_description]
      }

      response '201', 'work order created' do
        schema '$ref' => '#/components/schemas/WorkOrder'
        run_test!
      end

      response '422', 'unprocessable entity' do
        schema '$ref' => '#/components/schemas/Error'
        run_test!
      end

      response '401', 'unauthorized' do
        run_test!
      end
    end
  end

  path '/api/v1/work_orders/{id}' do
    get 'Get work order by ID' do
      tags 'Work Orders'
      produces 'application/json'
      security [ { bearerAuth: [] } ]
      parameter name: :id, in: :path, type: :integer, required: true

      response '200', 'successful' do
        schema '$ref' => '#/components/schemas/WorkOrder'
        run_test!
      end

      response '401', 'unauthorized' do
        run_test!
      end

      response '404', 'not found' do
        run_test!
      end
    end
  end

  path '/api/v1/work_orders/{id}/assign' do
    patch 'Assign mechanic' do
      tags 'Work Orders'
      consumes 'application/json'
      produces 'application/json'
      security [ { bearerAuth: [] } ]
      parameter name: :id, in: :path, type: :integer, required: true
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          mechanic_id: { type: :integer }
        },
        required: %w[mechanic_id]
      }

      response '200', 'mechanic assigned, status → diagnosing' do
        schema '$ref' => '#/components/schemas/WorkOrder'
        run_test!
      end

      response '422', 'unprocessable entity' do
        schema '$ref' => '#/components/schemas/Error'
        run_test!
      end

      response '401', 'unauthorized' do
        run_test!
      end
    end
  end

  path '/api/v1/work_orders/{id}/line_items' do
    post 'Add line item (service or part)' do
      tags 'Work Orders'
      consumes 'application/json'
      produces 'application/json'
      security [ { bearerAuth: [] } ]
      parameter name: :id, in: :path, type: :integer, required: true
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          item_type: { type: :string, enum: %w[service part] },
          reference_id: { type: :integer },
          quantity: { type: :integer }
        },
        required: %w[item_type reference_id quantity]
      }

      response '201', 'line item added' do
        schema '$ref' => '#/components/schemas/WorkOrder'
        run_test!
      end

      response '422', 'unprocessable entity' do
        schema '$ref' => '#/components/schemas/Error'
        run_test!
      end

      response '401', 'unauthorized' do
        run_test!
      end
    end
  end

  path '/api/v1/work_orders/{id}/diagnose' do
    patch 'Finalize diagnosis (status → awaiting_approval)' do
      tags 'Work Orders'
      produces 'application/json'
      security [ { bearerAuth: [] } ]
      parameter name: :id, in: :path, type: :integer, required: true

      response '200', 'diagnosis finalized' do
        schema '$ref' => '#/components/schemas/WorkOrder'
        run_test!
      end

      response '422', 'unprocessable entity' do
        schema '$ref' => '#/components/schemas/Error'
        run_test!
      end

      response '401', 'unauthorized' do
        run_test!
      end
    end
  end

  path '/api/v1/work_orders/{id}/reject' do
    patch 'Reject work order (status → rejected) — valid from received or diagnosing' do
      tags 'Work Orders'
      produces 'application/json'
      security [ { bearerAuth: [] } ]
      parameter name: :id, in: :path, type: :integer, required: true

      response '200', 'work order rejected' do
        schema '$ref' => '#/components/schemas/WorkOrder'
        run_test!
      end

      response '422', 'unprocessable entity' do
        schema '$ref' => '#/components/schemas/Error'
        run_test!
      end

      response '401', 'unauthorized' do
        run_test!
      end
    end
  end

  path '/api/v1/work_orders/{id}/deliver' do
    patch 'Deliver work order to customer (status → delivered)' do
      tags 'Work Orders'
      produces 'application/json'
      security [ { bearerAuth: [] } ]
      parameter name: :id, in: :path, type: :integer, required: true

      response '200', 'work order delivered' do
        schema '$ref' => '#/components/schemas/WorkOrder'
        run_test!
      end

      response '422', 'unprocessable entity' do
        schema '$ref' => '#/components/schemas/Error'
        run_test!
      end

      response '401', 'unauthorized' do
        run_test!
      end
    end
  end
end

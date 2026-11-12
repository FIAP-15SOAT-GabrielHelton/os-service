Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      namespace :auth do
        post :login, to: "sessions#create"
        post :customer, to: "customers#create"
        post :refresh, to: "tokens#refresh"
      end

      resources :customers, only: %i[index show create update destroy]

      resources :vehicles, only: %i[index show create update destroy]

      resources :inventory_items, only: %i[index show create update destroy] do
        member do
          patch :add_quantity
          patch :decrease_quantity
        end
      end

      resources :services, only: %i[index show create update destroy]

      namespace :admin do
        get :metrics, to: "metrics#show"
      end

      resources :work_orders, only: %i[index show create] do
        member do
          patch :assign
          patch :diagnose
          post :line_items, action: :add_line_item
          patch :reject
          patch :deliver
        end
      end

      get "tracking/:protocol", to: "tracking#show", as: :tracking
    end
  end

  mount Rswag::Api::Engine => "/api-docs"
  mount Rswag::Ui::Engine => "/api-docs"

  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?
end

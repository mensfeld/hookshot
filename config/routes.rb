# frozen_string_literal: true

Rails.application.routes.draw do
  # Public endpoints (no authentication)
  post "/webhooks/receive", to: "webhooks/receive#create"
  get "/health", to: "health#show"

  # Rails health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Job queue dashboard (with HTTP Basic Auth)
  mount MissionControl::Jobs::Engine, at: "/jobs"

  # Admin routes (HTTP Basic Auth)
  namespace :admin do
    resources :webhooks, only: %i[index show destroy] do
      member do
        post :replay
      end
    end

    resources :dispatches, only: %i[index show] do
      member do
        post :retry
      end
    end

    resources :targets do
      member do
        post :test
      end
    end
  end

  # Root redirects to admin webhooks
  root to: redirect("/admin/webhooks")
end

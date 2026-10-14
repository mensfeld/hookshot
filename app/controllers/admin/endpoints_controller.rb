# frozen_string_literal: true

module Admin
  # Manages endpoints: the inbound URLs webhooks are received on and the targets each one forwards to.
  class EndpointsController < AdminController
    before_action :set_endpoint, only: %i[show edit update destroy]

    # Lists all endpoints with their targets.
    # @return [void]
    def index
      @endpoints = Endpoint.includes(:targets).order(:name)
    end

    # Shows endpoint details.
    # @return [void]
    def show
    end

    # Renders the new endpoint form.
    # @return [void]
    def new
      @endpoint = Endpoint.new
    end

    # Renders the edit endpoint form.
    # @return [void]
    def edit
    end

    # Creates a new endpoint.
    # @return [void]
    def create
      @endpoint = Endpoint.new(endpoint_params)

      if @endpoint.save
        redirect_to admin_endpoint_path(@endpoint), notice: "Endpoint created successfully"
      else
        render :new, status: :unprocessable_entity
      end
    end

    # Updates an existing endpoint.
    # @return [void]
    def update
      if @endpoint.update(endpoint_params)
        redirect_to admin_endpoint_path(@endpoint), notice: "Endpoint updated successfully"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Deletes an endpoint. Its webhooks are kept without an endpoint; the default endpoint cannot be deleted.
    # @return [void]
    def destroy
      if @endpoint.destroy
        redirect_to admin_endpoints_path, notice: "Endpoint deleted successfully"
      else
        redirect_to admin_endpoint_path(@endpoint), alert: @endpoint.errors.full_messages.to_sentence
      end
    end

    private

    # Sets the endpoint from the ID parameter.
    # @return [void]
    def set_endpoint
      @endpoint = Endpoint.find(params[:id])
    end

    # Permits endpoint parameters.
    # @return [ActionController::Parameters] permitted parameters
    def endpoint_params
      params.require(:endpoint).permit(:name, :slug, :description, :active, target_ids: [])
    end
  end
end

# frozen_string_literal: true

module Admin
  # Manages delivery viewing and retry operations.
  class DispatchesController < AdminController
    before_action :set_delivery, only: %i[show retry]

    # Lists all deliveries with pagination and filtering.
    # @return [void]
    def index
      @deliveries = Delivery.includes(:webhook, :target).order(created_at: :desc)
      @deliveries = filter_deliveries(@deliveries)
      @deliveries = @deliveries.page(params[:page]).per(50)

      @targets = Target.order(:name)
    end

    # Shows delivery details.
    # @return [void]
    def show
    end

    # Retries a failed delivery.
    # @return [void]
    def retry
      unless @delivery.retryable?
        redirect_to admin_dispatch_path(@delivery), alert: "This delivery cannot be retried"
        return
      end

      @delivery.update!(status: :pending)
      DispatchJob.perform_later(@delivery.id)

      redirect_to admin_dispatch_path(@delivery), notice: "Delivery queued for retry"
    end

    private

    # Sets the delivery from the ID parameter.
    # @return [void]
    def set_delivery
      @delivery = Delivery.find(params[:id])
    end

    # Applies status and target filters to the deliveries scope.
    # @param scope [ActiveRecord::Relation] the base query scope
    # @return [ActiveRecord::Relation] filtered scope
    def filter_deliveries(scope)
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = scope.where(target_id: params[:target_id]) if params[:target_id].present?
      scope
    end
  end
end
